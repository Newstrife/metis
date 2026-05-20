class AddRuntimeStateToConversations < ActiveRecord::Migration[8.1]
  def change
    # Runtime-private state — each Agent::Runtime stashes what it needs to
    # resume (e.g. Runtime::E2b keeps its E2B sandbox id here). Distinct
    # from backend_session_id, which is the agent's (pi's) own resume token.
    add_column :conversations, :runtime_state, :jsonb, null: false, default: {}
  end
end
