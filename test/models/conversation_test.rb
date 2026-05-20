require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "conv@example.com", password: "password123")
    @conversation = @user.conversations.create!(backend: :pi)
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

  test "provider and model labels read from settings before a turn runs" do
    conversation = @user.conversations.create!(
      backend: :pi, settings: { "provider" => "openai", "model" => "gpt-5.5" }
    )
    assert_equal "openai", conversation.provider_label
    assert_equal "gpt-5.5", conversation.model_label
  end

  test "provider and model labels prefer the model pi resolved" do
    conversation = @user.conversations.create!(
      backend: :pi,
      settings: { "provider" => "openai", "model" => "gpt-5.5" },
      agent_model: { "provider" => "openai-codex", "name" => "GPT-5.5" }
    )
    assert_equal "openai-codex", conversation.provider_label
    assert_equal "GPT-5.5", conversation.model_label
  end

  test "provider and model labels are nil when nothing is known" do
    assert_nil @conversation.provider_label
    assert_nil @conversation.model_label
  end
end
