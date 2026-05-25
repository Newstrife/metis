# Generates a short AI title for a new conversation and broadcasts it to
# the sidebar and header via Turbo Streams.
#
# Triggered from Composing#start_turn after the first user message is
# saved. The title.blank? guard makes the job idempotent: a user who
# renames the conversation before the job runs won't have their title
# overwritten.
class GenerateConversationTitleJob < ApplicationJob
  queue_as :default

  TITLE_MAX = 60

  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)
    return if conversation.title.present?

    first_message = conversation.messages.where(role: :user).order(:created_at).first
    return unless first_message

    title = Agent::TitleGenerator.call(first_message.content) ||
            first_message.content.to_s.strip.truncate(TITLE_MAX, omission: "")

    conversation.update_column(:title, title.strip.truncate(TITLE_MAX, omission: ""))
    broadcast_title(conversation)
  rescue => e
    Rails.logger.error("GenerateConversationTitleJob #{conversation_id}: #{e.class}: #{e.message}")
  end

  private

  def broadcast_title(conversation)
    Turbo::StreamsChannel.broadcast_update_to(
      conversation,
      target: ActionView::RecordIdentifier.dom_id(conversation, :sidebar_title),
      html: ERB::Util.html_escape(conversation.display_title)
    )
    Turbo::StreamsChannel.broadcast_update_to(
      conversation,
      target: ActionView::RecordIdentifier.dom_id(conversation, :title),
      html: ERB::Util.html_escape(conversation.display_title)
    )
  end
end
