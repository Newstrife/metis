class AddArchivedAtToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :archived_at, :datetime
    add_index :conversations, :archived_at
  end
end
