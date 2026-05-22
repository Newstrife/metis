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
end
