class ConversationsController < ApplicationController
  include Composing

  layout "chat"

  before_action :set_conversation, only: %i[show cancel]
  before_action :set_sidebar, only: %i[index show]

  def index
    respond_to do |format|
      format.html
      # Endless-scroll fetch from the sidebar: only the incremental
      # page's groups are sent back, plus a refreshed sentinel. See
      # app/javascript/controllers/infinite_scroll_controller.js.
      format.turbo_stream
    end
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

  # Request that the in-flight turn stop. ChatJob picks this up and
  # aborts pi; the response is empty (the UI updates via broadcast).
  def cancel
    @conversation.request_cancel!
    head :no_content
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:id])
  end

  # The model picked in the new-chat composer, with its provider derived
  # from the catalog — stored on the conversation for the Pi adapter.
  # The composer's model picker wins; the user's profile default backs
  # it up when the picker submits blank (e.g. an out-of-catalog value
  # was scrubbed). Deployment defaults still kick in at the adapter
  # layer when both are unset.
  def chat_settings
    model = params[:model].presence || current_user.preferred_model.presence
    { "provider" => model && Agent::Catalog.provider_for(model), "model" => model }.compact
  end
end
