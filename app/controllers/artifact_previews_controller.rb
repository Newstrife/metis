class ArtifactPreviewsController < ApplicationController
  layout "preview"

  def show
    @blob = ActiveStorage::Blob.find_signed!(params[:signed_id])
    @message = message_for(@blob)
    raise ActiveRecord::RecordNotFound unless @message&.conversation&.team&.members&.include?(current_user)

    @previewer = ArtifactPreviewer.for(@blob)
    raise ActiveRecord::RecordNotFound unless @previewer.preview_partial
  end

  private

  # The blob has to be an :artifacts attachment on a Message — a
  # leaked signed_id for some other blob (a user upload, an avatar)
  # is not enough.
  def message_for(blob)
    Message.joins(:artifacts_attachments)
           .where(active_storage_attachments: { blob_id: blob.id, name: "artifacts" })
           .first
  end
end
