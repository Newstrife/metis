require "test_helper"

class GenerateConversationTitleJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "title-job@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @conversation.messages.create!(
      role: :user, content: "How do I set up a Rails 8 app?", streaming_status: :done
    )
  end

  test "writes the LLM-generated title via the model" do
    with_stub(Agent::TitleGenerator, :call, ->(_) { "Setting Up Rails 8" }) do
      GenerateConversationTitleJob.perform_now(@conversation.id)
    end

    assert_equal "Setting Up Rails 8", @conversation.reload.title
  end

  test "falls back to the first user message when the LLM returns nil" do
    with_stub(Agent::TitleGenerator, :call, ->(_) { nil }) do
      GenerateConversationTitleJob.perform_now(@conversation.id)
    end

    assert_equal "How do I set up a Rails 8 app?", @conversation.reload.title
  end

  test "skips generation when a title is already set" do
    @conversation.update!(title: "Already Named")
    call_count = 0
    with_stub(Agent::TitleGenerator, :call, ->(_) { call_count += 1; "New Name" }) do
      GenerateConversationTitleJob.perform_now(@conversation.id)
    end

    assert_equal 0, call_count
    assert_equal "Already Named", @conversation.reload.title
  end

  test "skips gracefully when the conversation has no user messages" do
    empty_conversation = @user.conversations.create!
    with_stub(Agent::TitleGenerator, :call, ->(_) { "Should Not Run" }) do
      GenerateConversationTitleJob.perform_now(empty_conversation.id)
    end

    assert_nil empty_conversation.reload.title
  end

  test "logs and swallows unexpected errors without re-raising" do
    with_stub(Agent::TitleGenerator, :call, ->(_) { raise "boom" }) do
      assert_nothing_raised do
        GenerateConversationTitleJob.perform_now(@conversation.id)
      end
    end
  end
end
