class AddShareTokenToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :share_token, :string
    add_index :conversations, :share_token, unique: true
  end
end
