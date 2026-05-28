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
    @user.conversations.create!(title: "Existing")
    sign_in @user
    get conversations_path
    assert_response :success
    assert_select ".sidebar .convo .tt", text: "Existing"
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

  test "new conversation starts with a blank title" do
    sign_in @user
    post conversations_path,
         params: { content: "Help me debug a Rails test", provider: "anthropic", model: "claude-opus-4-7" }

    assert_nil @user.conversations.last.title
  end

  test "rejects starting a chat with no message" do
    sign_in @user
    assert_no_difference -> { @user.conversations.count } do
      post conversations_path, params: { content: "   " }
    end
    assert_response :unprocessable_entity
  end

  test "share mints a token and renders the panel via turbo stream" do
    conversation = @user.conversations.create!(title: "to share")
    sign_in @user

    post share_conversation_path(conversation), as: :turbo_stream
    assert_response :success
    assert conversation.reload.shared?
    assert_match conversation.share_token, @response.body
  end

  test "share is idempotent and keeps the same token" do
    conversation = @user.conversations.create!(title: "stable")
    sign_in @user

    post share_conversation_path(conversation), as: :turbo_stream
    first_token = conversation.reload.share_token
    post share_conversation_path(conversation), as: :turbo_stream
    assert_equal first_token, conversation.reload.share_token
  end

  test "unshare clears the share token" do
    conversation = @user.conversations.create!(title: "revoke me")
    conversation.generate_share_token!
    sign_in @user

    delete share_conversation_path(conversation), as: :turbo_stream
    assert_response :success
    assert_nil conversation.reload.share_token
  end

  test "share is scoped to the current user's conversations" do
    other = User.create!(email: "other@example.com", password: "password123")
    conversation = other.conversations.create!(title: "not mine")
    sign_in @user

    post share_conversation_path(conversation), as: :turbo_stream
    assert_response :not_found
    assert_nil conversation.reload.share_token
  end

  test "sidebar paginates with a sentinel when more pages exist" do
    sign_in @user
    stub_const(ApplicationController, :SIDEBAR_PAGE_SIZE, 2) do
      3.times { |i| @user.conversations.create!(title: "Convo #{i}") }
      get conversations_path
      assert_response :success
      assert_select "nav.convos[data-controller~='infinite-scroll']"
      assert_select "#convos-sentinel[data-infinite-scroll-target='sentinel'][data-url*='page=2']"
      assert_select "#convos-list .convo", count: 2
    end
  end

  test "sidebar omits the sentinel when only one page exists" do
    sign_in @user
    @user.conversations.create!(title: "Only")
    get conversations_path
    assert_response :success
    assert_select "#convos-sentinel", count: 0
  end

  test "endless-scroll turbo_stream returns the next page of conversations" do
    sign_in @user
    stub_const(ApplicationController, :SIDEBAR_PAGE_SIZE, 2) do
      3.times { |i| @user.conversations.create!(title: "Convo #{i}") }
      get conversations_path(page: 2),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      # Append items before the sentinel, then remove it (last page).
      assert_match(/turbo-stream action="before" target="convos-sentinel"/, response.body)
      assert_match(/turbo-stream action="remove" target="convos-sentinel"/, response.body)
      assert_match(/Convo 0/, response.body)
    end
  end

  test "shows a conversation owned by the user" do
    sign_in @user
    conversation = @user.conversations.create!(title: "Mine")
    get conversation_path(conversation)
    assert_response :success
    assert_select "h1 span", text: "Mine"
  end

  test "shows the runtime a conversation ran on in the context meter" do
    sign_in @user
    conversation = @user.conversations.create!(
      title: "Ran", runtime_state: { "runtime" => "e2b", "sandbox_id" => "sbx-7" }
    )
    get conversation_path(conversation)

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(conversation, :context)}", /e2b/i
  end

  test "does not expose another user's conversation" do
    other = User.create!(email: "other@example.com", password: "password123")
    conversation = other.conversations.create!(title: "Secret")
    sign_in @user
    get conversation_path(conversation)
    assert_response :not_found
  end

  test "cancel stamps the conversation so the in-flight turn stops" do
    sign_in @user
    conversation = @user.conversations.create!(title: "Running")
    post cancel_conversation_path(conversation)

    assert_response :no_content
    assert_not_nil conversation.reload.cancel_requested_at
  end

  test "can rename a conversation" do
    sign_in @user
    conversation = @user.conversations.create!(title: "Old Title")
    patch conversation_path(conversation),
          params: { title: "New Title" },
          as: :json

    assert_response :ok
    assert_equal "New Title", conversation.reload.title
  end

  test "cannot rename a conversation to blank" do
    sign_in @user
    conversation = @user.conversations.create!(title: "Keep Me")
    patch conversation_path(conversation),
          params: { title: "   " },
          as: :json

    assert_response :unprocessable_entity
    assert_equal "Keep Me", conversation.reload.title
  end

  test "cannot rename another user's conversation" do
    other = User.create!(email: "rename-other@example.com", password: "password123")
    conversation = other.conversations.create!(title: "Theirs")
    sign_in @user

    patch conversation_path(conversation),
          params: { title: "Mine Now" },
          as: :json

    assert_response :not_found
    assert_equal "Theirs", conversation.reload.title
  end

  test "assign_project attaches the conversation to one of the user's projects" do
    project = @user.personal_team.projects.create!(name: "Metis")
    conversation = @user.conversations.create!
    sign_in @user

    patch project_conversation_path(conversation), params: { project_id: project.id }
    assert_response :success
    assert_equal project, conversation.reload.project
  end

  test "assign_project with blank project_id detaches the conversation" do
    project = @user.personal_team.projects.create!(name: "Metis")
    conversation = @user.conversations.create!(project: project)
    sign_in @user

    patch project_conversation_path(conversation), params: { project_id: "" }
    assert_response :success
    assert_nil conversation.reload.project_id
  end

  test "cannot attach a conversation to another team's project" do
    other_team = Team.create!(name: "Other")
    foreign_project = other_team.projects.create!(name: "Secret")
    conversation = @user.conversations.create!
    sign_in @user

    patch project_conversation_path(conversation), params: { project_id: foreign_project.id }
    assert_response :not_found
    assert_nil conversation.reload.project_id
  end

  # Temporarily override a constant for the duration of the block.
  # Lets us shrink SIDEBAR_PAGE_SIZE so the sentinel tests don't need
  # to create dozens of conversation fixtures.
  def stub_const(mod, name, value)
    original = mod.const_get(name)
    mod.send(:remove_const, name)
    mod.const_set(name, value)
    yield
  ensure
    mod.send(:remove_const, name)
    mod.const_set(name, original)
  end

  test "sidebar hides archived conversations" do
    sign_in @user
    @user.conversations.create!(title: "Visible")
    archived = @user.conversations.create!(title: "Hidden")
    archived.archive!

    get conversations_path
    assert_response :success
    assert_select "#convos-list .convo .tt", text: "Visible"
    assert_select "#convos-list .convo .tt", text: "Hidden", count: 0
  end

  test "archive marks a conversation as archived and redirects to root" do
    sign_in @user
    conversation = @user.conversations.create!(title: "Tidy")

    post archive_conversation_path(conversation)

    assert_redirected_to root_path
    assert conversation.reload.archived?
    assert_equal conversation.id, flash[:undo_archive_id]
  end

  test "archive is reversible via unarchive" do
    sign_in @user
    conversation = @user.conversations.create!(title: "Back")
    conversation.archive!

    post unarchive_conversation_path(conversation)

    refute conversation.reload.archived?
    assert_match(/restored/i, flash[:notice])
  end

  test "archived view lists only archived conversations" do
    sign_in @user
    @user.conversations.create!(title: "Live")
    archived = @user.conversations.create!(title: "Done")
    archived.archive!

    get archived_conversations_path

    assert_response :success
    assert_select ".archived-row", count: 1
    assert_select ".archived-row .archived-title", text: "Done"
  end

  test "showing an archived conversation still works (so it can be restored)" do
    sign_in @user
    conversation = @user.conversations.create!(title: "Frozen")
    conversation.archive!

    get conversation_path(conversation)
    assert_response :success
    assert_select ".archived-banner"
    assert_select ".archived-banner-action", text: "Restore"
  end

  test "cannot archive another user's conversation" do
    other = User.create!(email: "archive-other@example.com", password: "password123")
    conversation = other.conversations.create!(title: "Theirs")
    sign_in @user

    post archive_conversation_path(conversation)

    assert_response :not_found
    refute conversation.reload.archived?
  end

  test "cannot cancel another user's conversation" do
    other = User.create!(email: "cancel-other@example.com", password: "password123")
    conversation = other.conversations.create!(title: "Theirs")
    sign_in @user
    post cancel_conversation_path(conversation)

    assert_response :not_found
  end
end
