require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "conv@example.com", password: "password123")
    @conversation = @user.conversations.create!
  end

  test "a conversation defaults its team to the creator's personal team" do
    assert_equal @user.personal_team, @conversation.team
  end

  test "turn_in_progress? is false with no in-flight assistant message" do
    refute @conversation.turn_in_progress?
  end

  test "turn_in_progress? is true while an assistant message is pending or streaming" do
    message = @conversation.messages.create!(role: :assistant, content: "", streaming_status: :pending)
    assert @conversation.turn_in_progress?

    message.update!(streaming_status: :streaming)
    assert @conversation.turn_in_progress?

    message.update!(streaming_status: :done)
    refute @conversation.turn_in_progress?
  end

  test "the database forbids two in-flight assistant messages per conversation" do
    @conversation.messages.create!(role: :assistant, content: "", streaming_status: :pending)

    assert_raises(ActiveRecord::RecordNotUnique) do
      @conversation.messages.create!(role: :assistant, content: "", streaming_status: :streaming)
    end
  end

  test "a finished assistant message frees the next turn" do
    @conversation.messages.create!(role: :assistant, content: "done", streaming_status: :done)

    assert_nothing_raised do
      @conversation.messages.create!(role: :assistant, content: "", streaming_status: :pending)
    end
  end

  test "model_label reads from settings before a turn runs" do
    conversation = @user.conversations.create!(
      settings: { "provider" => "openai", "model" => "gpt-5.5" }
    )
    assert_equal "gpt-5.5", conversation.model_label
  end

  test "model_label prefers the model pi resolved" do
    conversation = @user.conversations.create!(
      settings: { "model" => "gpt-5.5" },
      agent_model: { "provider" => "openai-codex", "name" => "GPT-5.5" }
    )
    assert_equal "GPT-5.5", conversation.model_label
  end

  test "model_label and runtime_label are nil when nothing is known" do
    assert_nil @conversation.model_label
    assert_nil @conversation.runtime_label
  end

  test "runtime_label is the runtime the last turn ran on" do
    @conversation.update!(runtime_state: { "runtime" => "e2b", "sandbox_id" => "sbx-7" })
    assert_equal "e2b", @conversation.runtime_label
  end

  test "request_cancel! stamps cancel_requested_at" do
    assert_nil @conversation.cancel_requested_at
    @conversation.request_cancel!
    assert_not_nil @conversation.reload.cancel_requested_at
  end

  test "destroying a conversation kills its paused E2B sandbox" do
    # E2B keeps paused sandboxes indefinitely — without the destroy hook
    # every deleted conversation would leave a sandbox on E2B's servers
    # forever (docs/coding-runtime.md).
    @conversation.update_column(:e2b_sandbox_id, "sbx-doomed")
    killed_with = nil

    with_stub(Agent::Runtime::E2b, :kill_sandbox, ->(id) { killed_with = id }) do
      @conversation.destroy
    end

    assert_equal "sbx-doomed", killed_with
  end

  test "archive! stamps archived_at and unarchive! clears it" do
    refute @conversation.archived?
    assert Conversation.active.exists?(@conversation.id)
    refute Conversation.archived.exists?(@conversation.id)

    @conversation.archive!
    assert @conversation.archived?
    assert_not_nil @conversation.archived_at
    refute Conversation.active.exists?(@conversation.id)
    assert Conversation.archived.exists?(@conversation.id)

    @conversation.unarchive!
    refute @conversation.archived?
    assert_nil @conversation.archived_at
  end

  test "archive! is idempotent and does not move archived_at on a second call" do
    @conversation.archive!
    first_stamp = @conversation.archived_at
    travel 1.minute do
      @conversation.archive!
      assert_equal first_stamp, @conversation.reload.archived_at
    end
  end

  test "unarchive! is a no-op when the conversation is not archived" do
    assert_nothing_raised { @conversation.unarchive! }
    refute @conversation.archived?
  end

  test "destroying a conversation with no sandbox is a no-op for E2B" do
    called = false
    with_stub(Agent::Runtime::E2b, :kill_sandbox, ->(_id) { called = true }) do
      @conversation.destroy
    end
    # kill_sandbox itself is the guard against blank ids; it gets the
    # nil and short-circuits.
    assert called, "still invoked so the guard lives in one place"
  end
end
