module Agent
  # Polymorphic dispatch to backend adapters.
  #
  #   adapter = Agent::Adapters.for(conversation)
  #   adapter.stream("Write a haiku") { |ui_event| ... }
  #
  # v1 implements :pi. :claude_code and :codex are wired into the
  # Conversation backend enum but have no adapter yet — selecting them
  # raises UnsupportedBackendError, which the chat layer surfaces as a
  # "coming soon" notice.
  module Adapters
    SUPPORTED = %w[pi].freeze

    def self.for(conversation, **opts)
      unless supported?(conversation.backend)
        raise UnsupportedBackendError,
              "The #{conversation.backend} backend is not available yet."
      end

      Pi.new(conversation: conversation, **opts)
    end

    def self.supported?(backend)
      SUPPORTED.include?(backend.to_s)
    end
  end
end
