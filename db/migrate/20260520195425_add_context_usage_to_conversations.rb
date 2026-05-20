class AddContextUsageToConversations < ActiveRecord::Migration[8.1]
  def change
    # Latest pi contextUsage snapshot: { tokens:, contextWindow:, percent: }.
    add_column :conversations, :context_usage, :jsonb, default: {}, null: false
  end
end
