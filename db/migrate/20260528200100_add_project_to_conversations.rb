# A conversation optionally belongs to a Project. Nullable; no
# backfill — existing conversations stay detached, and the agent
# behaves exactly as today for them.
class AddProjectToConversations < ActiveRecord::Migration[8.1]
  def change
    add_reference :conversations, :project, foreign_key: true
  end
end
