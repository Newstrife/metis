require "shellwords"

module Agent
  module Runtime
    # Runs pi inside an E2B secure microVM — the isolated runtime.
    #
    # The microVM lives across turns: first turn creates it, subsequent
    # turns resume from the paused snapshot E2B keeps server-side. The
    # conversation's working tree, session transcript, installed
    # dependencies, and untracked WIP persist between turns by being
    # *the same VM*. See docs/coding-runtime.md.
    #
    # This IS an isolation boundary: pi's shell is confined to the
    # microVM — the host, Metis's secrets, and other conversations are
    # unreachable. The sandbox_id is recorded on the Conversation so
    # any worker can resume the same VM (worker fungibility — the state
    # lives in addressable remote storage, not in a worker process).
    #
    # Eviction is metis's responsibility: E2B does not auto-clean paused
    # sandboxes. EvictPausedSandboxesJob kills VMs whose conversation
    # has been idle past config.x.agent.e2b_eviction_window; the next
    # turn provisions a fresh one and the working tree is gone.
    #
    # pi must be present in the sandbox image (config.x.agent.e2b_template
    # — a template with pi baked in; see the e2b:template rake task).
    class E2b < Base
      SCOPE_DIR = "/home/user/metis".freeze
      SESSION_DIR = "#{SCOPE_DIR}/sessions".freeze
      WORKSPACE_DIR = "#{SCOPE_DIR}/workspace".freeze
      # Outside SCOPE_DIR on purpose — extensions are code shipped from
      # this app, restaged each turn rather than relied on to persist
      # via pause/resume (so a pi-extensions update reaches an existing
      # conversation on the next turn).
      EXTENSIONS_DIR = "/home/user/pi-extensions".freeze
      SANDBOX_TIMEOUT = 600

      # Kill a paused sandbox by id, swallowing the not-found case.
      # Used by Conversation#before_destroy and the eviction job —
      # places that hold a stored id but no live Sandbox handle.
      def self.kill_sandbox(sandbox_id)
        return if sandbox_id.blank?

        E2B::Sandbox.kill(sandbox_id)
      rescue E2B::NotFoundError
        # already gone — same outcome we wanted
      rescue E2B::E2BError => e
        Rails.logger.warn("E2B sandbox kill failed for sandbox_id=#{sandbox_id}: #{e.message}")
      end

      def session_dir
        Pathname.new(SESSION_DIR)
      end

      # The app's pi extensions at their planned in-sandbox paths. These
      # are deterministic so pi_args can be built before the sandbox
      # exists; #stage_extensions uploads the files to them.
      def extension_paths
        Agent::Runtime.extension_sources.map { |source| Pathname.new(sandbox_extension_path(source)) }
      end

      def run(pi_args:, &block)
        sandbox = acquire_sandbox
        @sandbox_id = sandbox.sandbox_id
        execute(sandbox, pi_args: pi_args, &block)
      ensure
        pause_sandbox(sandbox) if sandbox
      end

      # Adds the microVM's id, so a turn can be traced to its sandbox in
      # E2B's logs.
      def runtime_info
        super.merge("sandbox_id" => @sandbox_id)
      end

      private

      def execute(sandbox, pi_args:)
        provision(sandbox)
        stage_extensions(sandbox)
        stage_uploads(sandbox)
        stage_mcp_config(sandbox)
        stage_identity(sandbox)
        stage_skills(sandbox)
        session = PiAgent.session(transport_factory: transport_factory(sandbox, pi_args, sandbox_env))
        begin
          yield session
        ensure
          session.close
        end
      end

      # Resume the conversation's paused sandbox, or create one if there
      # isn't a usable one. A stored id that no longer resolves (E2B-side
      # cleanup, manual kill, ancient paused sandbox the eviction job
      # already collected) is cleared and we fall back to fresh provision.
      def acquire_sandbox
        if conversation.e2b_sandbox_id.present?
          resume_existing
        else
          create_fresh
        end
      end

      def resume_existing
        sandbox = E2B::Sandbox.connect(conversation.e2b_sandbox_id)
        sandbox.resume(timeout: SANDBOX_TIMEOUT)
        sandbox
      rescue E2B::NotFoundError
        Rails.logger.info(
          "E2B sandbox #{conversation.e2b_sandbox_id} not found for conversation " \
          "#{conversation.id}; provisioning fresh"
        )
        conversation.update_column(:e2b_sandbox_id, nil)
        create_fresh
      end

      def create_fresh
        E2B::Sandbox.create(template: template, timeout: SANDBOX_TIMEOUT)
      end

      # Pause the sandbox so the next turn can resume it; persist the id
      # if it changed (first turn) or was cleared. Logged-not-raised:
      # a pause failure at end-of-turn must not crash the turn the user
      # already saw. If pause fails we best-effort kill the VM so it
      # doesn't leak as a running orphan, and clear the id — next turn
      # will provision fresh.
      def pause_sandbox(sandbox)
        sandbox.pause
        conversation.update_column(:e2b_sandbox_id, sandbox.sandbox_id) \
          if conversation.e2b_sandbox_id != sandbox.sandbox_id
      rescue StandardError => e
        Rails.logger.warn("E2B sandbox pause failed for conversation #{conversation.id}: #{e.message}")
        force_kill_after_pause_failure(sandbox)
        conversation.update_column(:e2b_sandbox_id, nil)
      end

      def force_kill_after_pause_failure(sandbox)
        sandbox.kill
      rescue StandardError
        # nothing more to do — log was already written by pause_sandbox
      end

      def provision(sandbox)
        sandbox.commands.run("mkdir -p #{SESSION_DIR} #{WORKSPACE_DIR}/uploads")
      end

      # Upload the app's pi extensions into the sandbox so `pi --extension`
      # can load them. Re-staged each turn even on a resumed sandbox so
      # an update to a bundled extension reaches in-flight conversations.
      def stage_extensions(sandbox)
        sources = Agent::Runtime.extension_sources
        return if sources.empty?

        sandbox.commands.run("mkdir -p #{EXTENSIONS_DIR}")
        sources.each do |source|
          sandbox.files.write(sandbox_extension_path(source), File.binread(source))
        end
      end

      # An extension's path inside the sandbox. Each extension is a
      # <name>/index.ts; the upload is named <name>.ts so distinct
      # extensions do not collide on the shared index.ts basename.
      def sandbox_extension_path(source)
        "#{EXTENSIONS_DIR}/#{source.parent.basename}.ts"
      end

      # Project the conversation's uploaded files into uploads/. Re-
      # staged each turn (the canonical source is the Message
      # attachment, not the sandbox copy). Filenames are basenamed so a
      # crafted name cannot escape the uploads dir.
      def stage_uploads(sandbox)
        conversation.uploaded_files.each do |attachment|
          name = File.basename(attachment.filename.to_s)
          next if name.blank? || [ ".", ".." ].include?(name)

          sandbox.files.write("#{WORKSPACE_DIR}/uploads/#{name}", attachment.download)
        end
      end

      # Write the rendered .mcp.json into the sandbox workspace — a
      # per-turn projected input, overwriting any prior turn's copy.
      def stage_mcp_config(sandbox)
        sandbox.files.write("#{WORKSPACE_DIR}/#{Agent::McpConfig::FILENAME}", mcp_config)
      end

      # Write the rendered AGENTS.md into the sandbox workspace. Per-turn
      # projected input. pi auto-loads it from `cwd` as ambient
      # instructions.
      def stage_identity(sandbox)
        sandbox.files.write("#{WORKSPACE_DIR}/#{Agent::Identity::FILENAME}", identity_content)
      end

      # Project the repo's .pi/skills/ tree into the sandbox workspace.
      # pi auto-discovers skills from .pi/skills/ relative to cwd.
      # Per-turn projected input — the prior turn's tree is wiped first
      # so a deleted skill in the repo disappears from the sandbox.
      def stage_skills(sandbox)
        source = Agent::Workspace::SKILLS_SOURCE
        return unless source.directory?

        dest_root = "#{WORKSPACE_DIR}/#{Agent::Workspace::SKILLS_SUBPATH}"
        sandbox.commands.run("rm -rf #{Shellwords.escape(dest_root)}")
        Dir.glob(source.join("**/*"), File::FNM_DOTMATCH).each do |path|
          next if File.directory?(path)
          next if File.basename(path).match?(/\A\.{1,2}\z/)

          rel = Pathname.new(path).relative_path_from(source).to_s
          sandbox.files.write("#{dest_root}/#{rel}", File.binread(path))
        end
      end

      def transport_factory(sandbox, pi_args, envs)
        command = Shellwords.join([ "pi", *pi_args ])
        lambda do |on_message:, on_stderr:|
          E2bTransport.new(
            sandbox: sandbox, command: command, cwd: WORKSPACE_DIR, envs: envs,
            on_message: on_message, on_stderr: on_stderr
          )
        end
      end

      def template
        Rails.application.config.x.agent.e2b_template
      end
    end
  end
end
