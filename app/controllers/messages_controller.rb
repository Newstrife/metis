class MessagesController < ApplicationController
  before_action :set_conversation

  def create
    content = params[:content].to_s.strip
    return head(:unprocessable_entity) if content.blank?

    @user_message = @conversation.messages.create!(
      role: :user, content: content, streaming_status: :done
    )
    @assistant_message = @conversation.messages.create!(
      role: :assistant, content: "", streaming_status: :pending
    )

    ChatJob.perform_later(@conversation.id, @user_message.id, @assistant_message.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @conversation }
    end
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:conversation_id])
  end
end
