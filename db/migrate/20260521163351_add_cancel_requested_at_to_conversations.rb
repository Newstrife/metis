class AddCancelRequestedAtToConversations < ActiveRecord::Migration[8.1]
  def change
    # Stamped by the chat UI's Stop button; ChatJob polls it mid-stream
    # to abort the in-flight turn.
    add_column :conversations, :cancel_requested_at, :datetime
  end
end
