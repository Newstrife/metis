class RemoveBackendFromConversations < ActiveRecord::Migration[8.1]
  def change
    remove_column :conversations, :backend, :integer, default: 0, null: false
  end
end
