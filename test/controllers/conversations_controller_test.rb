require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "test@example.com", password: "password123")
  end

  test "redirects to sign in when not authenticated" do
    get conversations_path
    assert_redirected_to new_user_session_path
  end

  test "lists conversations for a signed-in user" do
    @user.conversations.create!(backend: :pi, title: "Existing")
    sign_in @user
    get conversations_path
    assert_response :success
    assert_select "h1", text: "Conversations"
  end

  test "starting a new chat creates a conversation with the first message" do
    sign_in @user
    assert_difference -> { @user.conversations.count }, 1 do
      assert_enqueued_with(job: ChatJob) do
        post conversations_path,
             params: { content: "first question", provider: "anthropic", model: "claude-opus-4-7" }
      end
    end

    conversation = @user.conversations.last
    assert_redirected_to conversation
    assert_equal "first question", conversation.messages.find_by(role: :user)&.content
    assert conversation.messages.exists?(role: :assistant, streaming_status: :pending)
  end

  test "stores the chosen provider and model on the conversation" do
    sign_in @user
    post conversations_path, params: { content: "hi", provider: "openai", model: "gpt-5.5" }

    settings = @user.conversations.last.settings
    assert_equal "openai", settings["provider"]
    assert_equal "gpt-5.5", settings["model"]
  end

  test "derives the conversation title from the first message" do
    sign_in @user
    post conversations_path,
         params: { content: "Help me debug a Rails test", provider: "anthropic", model: "claude-opus-4-7" }

    assert_equal "Help me debug a Rails test", @user.conversations.last.title
  end

  test "rejects starting a chat with no message" do
    sign_in @user
    assert_no_difference -> { @user.conversations.count } do
      post conversations_path, params: { content: "   " }
    end
    assert_response :unprocessable_entity
  end

  test "honors the chosen agent backend" do
    sign_in @user
    post conversations_path, params: { content: "hi", backend: "codex" }
    assert_equal "codex", @user.conversations.last.backend
  end

  test "falls back to pi for an unknown backend" do
    sign_in @user
    post conversations_path, params: { content: "hi", backend: "bogus" }
    assert_equal "pi", @user.conversations.last.backend
  end

  test "shows a conversation owned by the user" do
    sign_in @user
    conversation = @user.conversations.create!(backend: :pi, title: "Mine")
    get conversation_path(conversation)
    assert_response :success
    assert_select "h1", text: "Mine"
  end

  test "does not expose another user's conversation" do
    other = User.create!(email: "other@example.com", password: "password123")
    conversation = other.conversations.create!(backend: :pi, title: "Secret")
    sign_in @user
    get conversation_path(conversation)
    assert_response :not_found
  end
end
