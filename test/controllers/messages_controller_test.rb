require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "msg@example.com", password: "password123")
    @conversation = @user.conversations.create!(backend: :pi, title: "Chat")
    sign_in @user
  end

  test "creates a user message and assistant placeholder, enqueues ChatJob" do
    assert_difference -> { @conversation.messages.count }, 2 do
      assert_enqueued_with(job: ChatJob) do
        post conversation_messages_path(@conversation),
             params: { content: "Hello agent" }, as: :turbo_stream
      end
    end

    assert_response :success
    assert_equal "Hello agent", @conversation.messages.find_by(role: :user)&.content
    assert @conversation.messages.exists?(role: :assistant, streaming_status: :pending)
  end

  test "rejects a blank message" do
    assert_no_difference -> { @conversation.messages.count } do
      post conversation_messages_path(@conversation),
           params: { content: "   " }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "does not let a user post to another user's conversation" do
    other = User.create!(email: "other-msg@example.com", password: "password123")
    other_conversation = other.conversations.create!(backend: :pi)

    post conversation_messages_path(other_conversation),
         params: { content: "sneaky" }, as: :turbo_stream
    assert_response :not_found
  end

  test "requires authentication" do
    sign_out @user
    post conversation_messages_path(@conversation),
         params: { content: "hi" }, as: :turbo_stream
    assert_redirected_to new_user_session_path
  end
end
