class AddAgentModelToConversations < ActiveRecord::Migration[8.1]
  def change
    # The model pi actually resolved for the conversation:
    # { id:, name:, provider: }. Captured from pi's get_state each turn.
    add_column :conversations, :agent_model, :jsonb, default: {}, null: false
  end
end
