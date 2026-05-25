class GenerateConversationTitleJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)
    return if conversation.title.present?
    return unless conversation.messages.where(role: :user).exists?

    raw = Agent::TitleGenerator.call(conversation)
    conversation.apply_generated_title!(raw)
  rescue => e
    Rails.logger.error("GenerateConversationTitleJob #{conversation_id}: #{e.class}: #{e.message}")
  end
end
