class MessagesController < ApplicationController
  before_action :set_conversation

  def create
    content = params[:content].to_s.strip
    uploads = Array(params[:attachments]).reject(&:blank?)
    return head(:unprocessable_entity) if content.blank? && uploads.empty?
    return head(:conflict) if @conversation.turn_in_progress?

    if (error = upload_error(uploads))
      return render_composer_error(error)
    end

    create_messages(content, uploads)
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
  def create_messages(content, uploads)
    @conversation.transaction do
      @user_message = @conversation.messages.create!(
        role: :user, content: content, streaming_status: :done
      )
      attach_uploads(@user_message, uploads)
      @assistant_message = @conversation.messages.create!(
        role: :assistant, content: "", streaming_status: :pending
      )
    end
  end

  # Images go to the agent inline; other files are staged into its
  # workspace. They are split here by content type.
  def attach_uploads(message, uploads)
    images, files = uploads.partition { |u| u.content_type.to_s.start_with?("image/") }
    message.images.attach(images) if images.any?
    message.files.attach(files) if files.any?
  end

  # First problem with an upload, or nil when they all pass.
  def upload_error(uploads)
    uploads.each do |upload|
      if upload.size > Message::MAX_UPLOAD_SIZE
        return "#{upload.original_filename} is too large (max #{Message::MAX_UPLOAD_SIZE / 1.megabyte} MB)."
      end
      unless Message::ALLOWED_CONTENT_TYPES.include?(upload.content_type)
        return "#{upload.original_filename} has an unsupported file type."
      end
    end
    nil
  end

  def render_composer_error(error)
    render(
      turbo_stream: turbo_stream.replace(
        "composer",
        partial: "conversations/composer",
        locals: { conversation: @conversation, error: error }
      ),
      status: :unprocessable_entity
    )
  end

  def set_conversation
    @conversation = current_user.conversations.find(params[:conversation_id])
  end
end
