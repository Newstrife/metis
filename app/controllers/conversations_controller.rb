class ConversationsController < ApplicationController
  include Composing

  layout "chat"

  before_action :set_conversation, only: %i[show cancel archive unarchive update share unshare assign_project]
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

    conversation = current_user.conversations.create!(settings: chat_settings)
    start_turn(conversation, content, uploads)
    redirect_to conversation
  end

  def show
    @messages = @conversation.messages.chronological
  end

  # PATCH /conversations/:id — title-only rename. Driven by the
  # conversation-title Stimulus controller.
  def update
    title = params[:title].to_s.strip
    return head(:unprocessable_entity) if title.blank?

    @conversation.update!(title: title)
    @conversation.broadcast_title_change!
    head :ok
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

  def share
    @conversation.generate_share_token!
    respond_to do |format|
      format.turbo_stream { render "conversations/share" }
      format.html { redirect_to @conversation }
    end
  end

  def unshare
    @conversation.revoke_share!
    respond_to do |format|
      format.turbo_stream { render "conversations/share" }
      format.html { redirect_to @conversation }
    end
  end

  # PATCH /conversations/:id/project — attach or detach. Blank
  # project_id detaches; non-blank must belong to the conversation's
  # own team (scoped finder raises 404 otherwise). The chip is a
  # Turbo Frame, so the response is the same partial: Turbo finds
  # the matching frame ID and replaces its contents in place. No
  # turbo_stream + respond_to gymnastics — the share/unshare pattern
  # uses streams to retarget DOM by id, but this update is wholly
  # self-contained inside the frame.
  def assign_project
    project_id = params[:project_id].to_s.strip
    project = project_id.present? ? @conversation.team.projects.find(project_id) : nil
    @conversation.update!(project: project)
    render partial: "conversations/project_chip", locals: { conversation: @conversation }
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
