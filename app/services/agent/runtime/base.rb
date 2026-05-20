module Agent
  module Runtime
    # Interface every runtime implements. A runtime decides where the
    # agent process physically runs and how its filesystem persists.
    class Base
      attr_reader :conversation

      def initialize(conversation:)
        @conversation = conversation
      end

      # Directory the agent should pass to `pi --session-dir`.
      def session_dir
        raise NotImplementedError, "#{self.class} must implement #session_dir"
      end

      # Provision the runtime, open a PiAgent::Session running pi with
      # `pi_args`, yield it to the caller, then finalize (persist state,
      # tear down). The session is closed by the runtime, not the caller.
      #
      # `files` are uploaded files (responding to #filename and #open)
      # staged into pi's working directory before the run — a filesystem
      # operation, so each runtime stages them its own way.
      def run(pi_args:, files: [])
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      # A record of where the turn ran, persisted on the Conversation:
      # the runtime name, plus whatever per-run detail a subclass adds.
      def runtime_info
        { "runtime" => self.class.name.demodulize.underscore }
      end
    end
  end
end
