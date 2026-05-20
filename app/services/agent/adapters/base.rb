module Agent
  module Adapters
    # Interface every backend adapter implements. An adapter drives one
    # conversation's backend and yields Agent::UiEvent objects.
    class Base
      attr_reader :conversation

      def initialize(conversation:, **opts)
        @conversation = conversation
        @opts = opts
      end

      # Run +input+ against the backend, yielding Agent::UiEvent objects
      # until the turn finishes. Returns an Enumerator if no block given.
      def stream(input, &block)
        raise NotImplementedError, "#{self.class} must implement #stream"
      end

      # Abort the in-flight run, if any.
      def abort
        raise NotImplementedError, "#{self.class} must implement #abort"
      end

      # Backend-native session id, persisted on the Conversation so the
      # next turn can resume. nil if the backend has no resumable session.
      def native_session_id
        nil
      end
    end
  end
end
