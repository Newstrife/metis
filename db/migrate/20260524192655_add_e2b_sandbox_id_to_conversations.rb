class AddE2bSandboxIdToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :e2b_sandbox_id, :string
    add_index :conversations, :e2b_sandbox_id
  end
end
