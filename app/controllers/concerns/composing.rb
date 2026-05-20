# Shared message-composing behavior for starting an agent turn — used by
# both MessagesController (existing conversations) and
# ConversationsController (the new-chat composer on the index).
module Composing
  extend ActiveSupport::Concern

  private

  def composed_content
    params[:content].to_s.strip
  end

  def composed_uploads
    Array(params[:attachments]).reject(&:blank?)
  end

  # Create the user + assistant messages for one turn, attach uploads,
  # and enqueue the run. Returns [user_message, assistant_message].
  #
  # Both rows are written in one transaction so a turn-guard collision
  # on the assistant row rolls the user message back too — no orphan.
  def start_turn(conversation, content, uploads)
    user_message = assistant_message = nil
    conversation.transaction do
      user_message = conversation.messages.create!(
        role: :user, content: content, streaming_status: :done
      )
      attach_uploads(user_message, uploads)
      # Stamped at send time so duration spans the queue wait too.
      assistant_message = conversation.messages.create!(
        role: :assistant, content: "", streaming_status: :pending, started_at: Time.current
      )
    end
    ChatJob.perform_later(conversation.id, user_message.id, assistant_message.id)
    [ user_message, assistant_message ]
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

  # Re-render the composer with an error. `conversation` is nil for the
  # new-chat composer on the conversations index.
  def render_composer_error(conversation, error)
    render(
      turbo_stream: turbo_stream.replace(
        "composer",
        partial: "conversations/composer",
        locals: { conversation: conversation, error: error }
      ),
      status: :unprocessable_entity
    )
  end
end
