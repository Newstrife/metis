class AddReasoningAndToolCallsToMessages < ActiveRecord::Migration[8.1]
  def change
    # The assistant's thinking, accumulated from reasoning_delta events
    # (encrypted, like content).
    add_column :messages, :reasoning, :text
    # The turn's tool calls: [{ tool_call_id, name, args, output,
    # is_error, status }, ...].
    add_column :messages, :tool_calls, :jsonb, default: [], null: false
  end
end
