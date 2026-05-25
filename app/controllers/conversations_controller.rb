class ConversationsController < ApplicationController
  include Composing

  layout "chat"

  before_action :set_conversation, only: %i[show cancel archive unarchive]
  before_action :set_sidebar, only: %i[index show archived]

  def index
    respond_to do |format|
      format.html
      # Endless-scroll fetch from the sidebar: only the incremental
      # page's groups are sent back, plus a refreshed sentinel. See
      # app/javascript/controllers/infinite_scroll_controller.js.
      # Guarded by `page` so Turbo Drive form redirects (which advertise
      # turbo-stream in their Accept header) get a full HTML page back
      # instead of a stream meant to append into an existing sidebar.
      format.turbo_stream if params[:page].present?
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

  # The "Archived" view: same chrome as the main sidebar, but the right
  # pane lists every archived conversation with an unarchive action.
  # The sidebar itself still shows the *active* list — archived items
  # are deliberately not mixed in.
  def archived
    @archived_conversations = current_user.conversations.archived.recent
  end

  # Soft-archive. If the user archived the conversation they had open,
  # bounce them to the new-chat root so they aren't staring at a row
  # that no longer belongs in the active sidebar.
  # Sidebar and header buttons both submit with `turbo_frame: "_top"`,
  # so the redirect causes a full top-level visit — the sidebar
  # re-renders without the archived row, and the user lands on a fresh
  # inbox/new-chat. The id is stashed in flash so the toast can offer an
  # Undo (see app/views/layouts/chat.html.erb).
  def archive
    @conversation.archive!
    flash[:notice] = "Conversation archived."
    flash[:undo_archive_id] = @conversation.id
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
