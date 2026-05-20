class AddInProgressTurnGuardToMessages < ActiveRecord::Migration[8.1]
  def change
    # At most one in-flight assistant message per conversation — the
    # airtight backstop for "one turn at a time", so concurrent ChatJobs
    # can't race on a conversation's scratch directory.
    #
    # role = 1 is :assistant; streaming_status 0/1 are :pending/:streaming
    # (see the Message model enums).
    add_index :messages, :conversation_id,
              unique: true,
              where: "role = 1 AND streaming_status IN (0, 1)",
              name: "index_messages_on_one_in_progress_turn"
  end
end
