class ConversationsController < ApplicationController
  include Composing

  layout "chat"

  before_action :set_conversation, only: %i[show cancel archive unarchive]
  before_action :set_sidebar, only: %i[index show archived]

  def index
    respond_to do |format|
      format.html
      # Gated on :page so Turbo Drive form redirects don't get the scroll stream.
      format.turbo_stream if params[:page].present?
    end
  end

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

  def cancel
    @conversation.request_cancel!
    head :no_content
  end

  def archived
    @archived_conversations = current_user.conversations.archived.recent
  end

  def archive
    @conversation.archive!
    flash[:notice] = "Conversation archived."
    flash[:undo_archive_id] = @conversation.id # consumed by the toast Undo
    redirect_to root_path
  end

  def unarchive
    @conversation.unarchive!
    flash[:notice] = "Conversation restored."
    redirect_to @conversation
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:id])
  end

  # Composer wins; profile default backs up a scrubbed pick; both blank →
  # adapter falls back to deployment defaults.
  def chat_settings
    model = params[:model].presence || current_user.preferred_model.presence
    { "provider" => model && Agent::Catalog.provider_for(model), "model" => model }.compact
  end
end
