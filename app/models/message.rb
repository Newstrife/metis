class Message < ApplicationRecord
  enum :role, { user: 0, assistant: 1, tool: 2, system: 3 }
  enum :streaming_status, { pending: 0, streaming: 1, done: 2, errored: 3 }

  belongs_to :conversation

  encrypts :content

  scope :chronological, -> { order(:created_at) }
end
