class ArtifactPreviewsController < ApplicationController
  layout "preview"

  def show
    @blob = ActiveStorage::Blob.find_signed!(params[:signed_id])
    @message = message_for(@blob)
    raise ActiveRecord::RecordNotFound unless @message&.conversation&.team&.members&.include?(current_user)

    @previewer = ArtifactPreviewer.for(@blob)
    raise ActiveRecord::RecordNotFound if @previewer.preview_modes.empty?

    @mode = resolve_mode
    @partial = @previewer.partial_for_mode(@mode)
  end

  private

  def resolve_mode
    requested = params[:mode]&.to_sym
    return requested if @previewer.preview_modes.include?(requested)

    @previewer.default_mode
  end

  # The blob has to be an :artifacts attachment on a Message — a
  # leaked signed_id for some other blob (a user upload, an avatar)
  # is not enough.
  def message_for(blob)
    Message.joins(:artifacts_attachments)
           .where(active_storage_attachments: { blob_id: blob.id, name: "artifacts" })
           .first
  end
end
