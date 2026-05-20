require "shellwords"

module Agent
  module Runtime
    # Runs pi inside an E2B secure microVM — the isolated runtime.
    #
    # Each conversation owns one sandbox: created on the first turn,
    # paused after each turn, resumed on the next (pi's session directory
    # and workspace persist in the frozen microVM). The sandbox id is kept
    # in Conversation#runtime_state. An expired/missing sandbox falls back
    # to a fresh one.
    #
    # This IS an isolation boundary: pi's shell is confined to the
    # microVM — the host, Metis's secrets, and other conversations are
    # unreachable.
    #
    # pi must be present in the sandbox image (config.x.agent.e2b_template
    # — a template with pi baked in; see lib/tasks or the build script).
    class E2b < Base
      SESSION_DIR = "/home/user/metis/sessions".freeze
      WORKSPACE_DIR = "/home/user/metis/workspace".freeze
      SANDBOX_TIMEOUT = 600

      def session_dir
        Pathname.new(SESSION_DIR)
      end

      def run(pi_args:)
        sandbox = acquire_sandbox
        provision(sandbox)
        session = PiAgent.session(transport_factory: transport_factory(sandbox, pi_args))
        begin
          yield session
        ensure
          session.close
          finalize(sandbox)
        end
      end

      private

      def acquire_sandbox
        id = conversation.runtime_state["e2b_sandbox_id"]
        if id.present?
          begin
            return resume_sandbox(id)
          rescue E2B::E2BError => e
            Rails.logger.warn("E2B resume failed for conversation #{conversation.id} " \
                              "(#{e.message}); creating a fresh sandbox")
          end
        end
        create_sandbox
      end

      def resume_sandbox(id)
        sandbox = E2B::Sandbox.connect(id, timeout: SANDBOX_TIMEOUT)
        sandbox.resume(timeout: SANDBOX_TIMEOUT)
        sandbox
      end

      def create_sandbox
        E2B::Sandbox.create(template: template, timeout: SANDBOX_TIMEOUT)
      end

      def provision(sandbox)
        sandbox.commands.run("mkdir -p #{SESSION_DIR} #{WORKSPACE_DIR}")
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

      # Pause the sandbox (freezing pi's session + workspace) and record
      # its id so the next turn resumes it. Failures are logged, never
      # raised — they must not crash a turn the user already saw.
      def finalize(sandbox)
        sandbox.pause
        conversation.update_column(
          :runtime_state, conversation.runtime_state.merge("e2b_sandbox_id" => sandbox.sandbox_id)
        )
      rescue E2B::E2BError, ActiveRecord::ActiveRecordError => e
        Rails.logger.error("E2B finalize failed for conversation #{conversation.id}: #{e.message}")
      end

      def template
        Rails.application.config.x.agent.e2b_template
      end
    end
  end
end
