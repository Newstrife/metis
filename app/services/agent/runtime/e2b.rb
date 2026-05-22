require "shellwords"
require "tempfile"

module Agent
  module Runtime
    # Runs pi inside an E2B secure microVM — the isolated runtime.
    #
    # The microVM is disposable execution infrastructure, not the
    # conversation's memory. Each turn: a fresh sandbox is created,
    # hydrated from the conversation's durable archive (Active Storage),
    # runs pi, has its scope captured back to the archive, and is killed.
    # State lives outside E2B — an expired or unreachable sandbox costs
    # nothing and loses nothing.
    #
    # This IS an isolation boundary: pi's shell is confined to the
    # microVM — the host, Metis's secrets, and other conversations are
    # unreachable.
    #
    # pi must be present in the sandbox image (config.x.agent.e2b_template
    # — a template with pi baked in; see the e2b:template rake task).
    class E2b < Base
      SCOPE_DIR = "/home/user/metis".freeze
      SESSION_DIR = "#{SCOPE_DIR}/sessions".freeze
      WORKSPACE_DIR = "#{SCOPE_DIR}/workspace".freeze
      # Outside SCOPE_DIR on purpose — extensions are code, not session
      # state, and must not be captured into the conversation's archive.
      EXTENSIONS_DIR = "/home/user/pi-extensions".freeze
      REMOTE_ARCHIVE = "/tmp/pi-session.tar.gz".freeze
      SANDBOX_TIMEOUT = 600

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
        sandbox = create_sandbox
        @sandbox_id = sandbox.sandbox_id
        execute(sandbox, pi_args: pi_args, &block)
      ensure
        terminate(sandbox)
      end

      # Adds the microVM's id, so a turn can be traced to its sandbox in
      # E2B's logs even though the sandbox itself is killed after the run.
      def runtime_info
        super.merge("sandbox_id" => @sandbox_id)
      end

      private

      def execute(sandbox, pi_args:)
        provision(sandbox)
        stage_extensions(sandbox)
        hydrate(sandbox)
        stage_uploads(sandbox)
        stage_mcp_config(sandbox)
        session = PiAgent.session(transport_factory: transport_factory(sandbox, pi_args))
        begin
          yield session
        ensure
          session.close
          persist(sandbox)
        end
      end

      def create_sandbox
        E2B::Sandbox.create(template: template, timeout: SANDBOX_TIMEOUT)
      end

      def provision(sandbox)
        sandbox.commands.run("mkdir -p #{SESSION_DIR} #{WORKSPACE_DIR}/uploads")
      end

      # Restore the conversation's durable archive into the sandbox. No-op
      # on the first turn (no archive yet).
      def hydrate(sandbox)
        Agent::SessionArchive.with_archive(conversation) do |archive_path|
          sandbox.files.write(REMOTE_ARCHIVE, File.binread(archive_path))
          sandbox.commands.run("tar -xzf #{REMOTE_ARCHIVE} -C #{SCOPE_DIR}")
        end
      end

      # Capture the sandbox's scope (session + workspace) back to durable
      # storage. Logged, never raised — it must not crash the turn the
      # user already saw stream.
      def persist(sandbox)
        # Exclude per-turn projected inputs (staged uploads, the
        # rendered .mcp.json) — not archived state.
        sandbox.commands.run(
          "tar -czf #{REMOTE_ARCHIVE} -C #{SCOPE_DIR} " \
          "--exclude=./workspace/uploads --exclude=./workspace/.mcp.json ."
        )
        data = sandbox.files.read(REMOTE_ARCHIVE, format: "bytes")
        Tempfile.create([ "pi-session", ".tar.gz" ]) do |tmp|
          tmp.binmode
          tmp.write(data)
          tmp.flush
          Agent::SessionArchive.attach(conversation, tmp.path)
        end
      rescue StandardError => e
        Rails.logger.error("E2B archive failed for conversation #{conversation.id}: #{e.message}")
      end

      # Upload the app's pi extensions into the sandbox so `pi --extension`
      # can load them. Written outside SCOPE_DIR — they are code, and must
      # not be captured into the conversation's session archive.
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

      # Project the conversation's uploaded files into uploads/. They are
      # excluded from the archive (durable as Message attachments), so
      # all of them are re-staged into the fresh sandbox every turn.
      # Filenames are basenamed so a crafted name cannot escape.
      def stage_uploads(sandbox)
        conversation.uploaded_files.each do |attachment|
          name = File.basename(attachment.filename.to_s)
          next if name.blank? || [ ".", ".." ].include?(name)

          sandbox.files.write("#{WORKSPACE_DIR}/uploads/#{name}", attachment.download)
        end
      end

      # Write the rendered .mcp.json into the sandbox workspace — a
      # per-turn projected input, excluded from the archive (see #persist).
      def stage_mcp_config(sandbox)
        sandbox.files.write("#{WORKSPACE_DIR}/#{Agent::McpConfig::FILENAME}", mcp_config)
      end

      def transport_factory(sandbox, pi_args)
        command = Shellwords.join([ "pi", *pi_args ])
        lambda do |on_message:, on_stderr:|
          E2bTransport.new(
            sandbox: sandbox, command: command, cwd: WORKSPACE_DIR,
            on_message: on_message, on_stderr: on_stderr
          )
        end
      end

      def terminate(sandbox)
        sandbox&.kill
      rescue E2B::E2BError => e
        Rails.logger.warn("E2B sandbox kill failed for conversation #{conversation.id}: #{e.message}")
      end

      def template
        Rails.application.config.x.agent.e2b_template
      end
    end
  end
end
