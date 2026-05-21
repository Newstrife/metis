module Agent
  # Builds the coding-agent adapter for a conversation.
  #
  #   adapter = Agent::Adapters.for(conversation)
  #   adapter.stream("Write a haiku") { |ui_event| ... }
  #
  # Metis runs on a single coding-agent foundation — pi. This layer keeps
  # the chat UI decoupled from pi's wire protocol; it is not a
  # multi-backend seam. See docs/single-coding-agent-foundation.md.
  module Adapters
    def self.for(conversation, **opts)
      Pi.new(conversation: conversation, **opts)
    end
  end
end
