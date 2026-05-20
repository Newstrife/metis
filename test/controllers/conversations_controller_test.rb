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

  test "creates a conversation and redirects to it" do
    sign_in @user
    assert_difference -> { @user.conversations.count }, 1 do
      post conversations_path, params: { conversation: { title: "New work", backend: "pi" } }
    end
    assert_redirected_to conversation_path(@user.conversations.last)
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
