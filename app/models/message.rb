class Message < ApplicationRecord
  enum :role, { user: 0, assistant: 1, tool: 2, system: 3 }
  enum :streaming_status, { pending: 0, streaming: 1, done: 2, errored: 3 }

  belongs_to :conversation

  # Composer uploads. Images are sent to the agent inline (pi's vision
  # protocol); other files are staged into the agent's workspace so it
  # can open them with its file tools. See Agent::Adapters::Pi.
  has_many_attached :images
  has_many_attached :files

  encrypts :content

  ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  ALLOWED_FILE_TYPES = %w[
    application/pdf
    text/plain text/csv text/markdown
    application/json application/xml text/xml
  ].freeze
  ALLOWED_CONTENT_TYPES = (ALLOWED_IMAGE_TYPES + ALLOWED_FILE_TYPES).freeze
  MAX_UPLOAD_SIZE = 10.megabytes

  scope :chronological, -> { order(:created_at) }

  def attachments?
    images.attached? || files.attached?
  end
end
