class ConversationsController < ApplicationController
  include Composing

  before_action :set_conversation, only: :show

  def index
    @conversations = current_user.conversations.recent
  end

  # A new conversation starts from its first message: the index composer
  # posts content (and the picked provider/model) straight here.
  def create
    content = composed_content
    uploads = composed_uploads

    if content.blank? && uploads.empty?
      return render_composer_error(nil, "Type a message to start a conversation.")
    end
    if (error = upload_error(uploads))
      return render_composer_error(nil, error)
    end

    conversation = current_user.conversations.create!(
      title: content.presence&.truncate(80), settings: chat_settings
    )
    start_turn(conversation, content, uploads)
    redirect_to conversation
  end

  def show
    @messages = @conversation.messages.chronological
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:id])
  end

  # The provider/model picked in the new-chat composer, stored on the
  # conversation for Agent::Adapters::Pi#credential_args.
  def chat_settings
    { "provider" => params[:provider].presence, "model" => params[:model].presence }.compact
  end
end
