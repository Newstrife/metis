require "securerandom"

module Agent
  module Runtime
    # Runs pi inside a Docker container — the middle isolation tier.
    #
    # `docker run -i` wires the container's stdio to the docker client
    # process, so pi-in-a-container is driven through pi-agent-rb's plain
    # subprocess transport — no custom transport is needed (cf. E2b,
    # which bridges an HTTP API).
    #
    # The conversation's scope directory is bind-mounted into the
    # container. The container is disposable — fresh per turn, removed
    # after — so the scope is scratch, restored from / captured back to
    # the durable archive (Agent::SessionArchive) around each run. See
    # docs/session-persistence.md.
    #
    # Isolation: namespace + cgroup confinement and dropped capabilities
    # — stronger than Local (pi cannot reach the host filesystem beyond
    # the mounts, or host processes), weaker than E2b (a shared kernel,
    # not a microVM). Suitable for trusted, self-hosted multi-user use.
    #
    # Assumes the worker has direct access to a Docker daemon and can
    # bind-mount host paths (not Docker-in-Docker). pi must be installed
    # in the image (config.x.agent.docker_image — see docker:image).
    class Docker < Base
      # The conversation scope, bind-mounted from the host Workspace.
      SCOPE_DIR = "/metis".freeze
      SESSION_DIR = "#{SCOPE_DIR}/sessions".freeze
      WORKSPACE_DIR = "#{SCOPE_DIR}/workspace".freeze
      # The app's pi extensions, bind-mounted read-only — code, not
      # session state, so kept out of the archived scope.
      EXTENSIONS_DIR = "/metis-extensions".freeze

      def session_dir
        Pathname.new(SESSION_DIR)
      end

      # The app's pi extensions at their in-container paths, under the
      # read-only extensions mount (#docker_args bind-mounts the dir).
      def extension_paths
        Agent::Runtime.extension_sources.map do |source|
          Pathname.new("#{EXTENSIONS_DIR}/#{source.parent.basename}/#{source.basename}")
        end
      end

      def run(pi_args:)
        workspace.reset!
        Agent::SessionArchive.restore(conversation, into: workspace.scope_dir)
        workspace.stage_uploads(conversation.uploaded_files)
        workspace.stage_mcp_config(mcp_config)
        session = PiAgent.session(bin: "docker", args: docker_args(pi_args))
        begin
          yield session
        ensure
          session.close
          remove_container
          persist
        end
      end

      # Adds the container name, so a turn can be traced even though the
      # container is removed after the run.
      def runtime_info
        super.merge("container" => container_name)
      end

      private

      def workspace
        @workspace ||= Agent::Workspace.scratch(conversation)
      end

      def container_name
        @container_name ||= "metis-c#{conversation.id}-#{SecureRandom.hex(4)}"
      end

      # `docker run` flags wrapping `pi <pi_args>`. The container runs as
      # the host uid so files on the bind mount stay owned by this
      # process (which archives them); capabilities are dropped and
      # resources capped. --pull never: the image is built locally.
      def docker_args(pi_args)
        [
          "run", "--rm", "-i",
          "--pull", "never",
          "--name", container_name,
          "--user", "#{Process.uid}:#{Process.gid}",
          "--volume", "#{workspace.scope_dir}:#{SCOPE_DIR}",
          *extension_mount,
          "--workdir", WORKSPACE_DIR,
          "--env", "HOME=/tmp",
          "--memory", "2g", "--cpus", "2", "--pids-limit", "512",
          "--cap-drop", "ALL",
          "--security-opt", "no-new-privileges",
          image,
          "pi", *pi_args
        ]
      end

      def extension_mount
        return [] if Agent::Runtime.extension_sources.empty?

        [ "--volume", "#{Rails.root.join('.pi/extensions')}:#{EXTENSIONS_DIR}:ro" ]
      end

      # Force-remove the container — a net for when the docker client was
      # killed before --rm could fire (e.g. an aborted turn). Best effort.
      def remove_container
        system("docker", "rm", "--force", container_name, out: File::NULL, err: File::NULL)
      end

      # Capture the scratch scope back to durable storage (uploads
      # excluded — see SessionArchive). A persistence failure is logged,
      # never raised — it must not crash the turn the user just saw.
      def persist
        Agent::SessionArchive.store(conversation, from: workspace.scope_dir)
      rescue StandardError => e
        Rails.logger.error("Runtime::Docker archive failed for conversation #{conversation.id}: #{e.message}")
      end

      def image
        Rails.application.config.x.agent.docker_image
      end
    end
  end
end
