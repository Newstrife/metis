class MessagesController < ApplicationController
  before_action :set_conversation

  def create
    content = params[:content].to_s.strip
    return head(:unprocessable_entity) if content.blank?
    return head(:conflict) if @conversation.turn_in_progress?

    create_messages(content)
    ChatJob.perform_later(@conversation.id, @user_message.id, @assistant_message.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @conversation }
    end
  rescue ActiveRecord::RecordNotUnique
    # The in-progress-turn index caught a race the pre-check missed.
    head(:conflict)
  end

  private

  # Both messages in one transaction so a turn-guard collision on the
  # assistant row rolls the user message back too — no orphan.
  def create_messages(content)
    @conversation.transaction do
      @user_message = @conversation.messages.create!(
        role: :user, content: content, streaming_status: :done
      )
      @assistant_message = @conversation.messages.create!(
        role: :assistant, content: "", streaming_status: :pending
      )
    end
  end

  def set_conversation
    @conversation = current_user.conversations.find(params[:conversation_id])
  end
end
