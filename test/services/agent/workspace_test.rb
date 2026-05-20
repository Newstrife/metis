require "test_helper"

class Agent::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "ws@example.com", password: "password123")
    @conversation = @user.conversations.create!(backend: :pi)
  end

  test "session_dir is scoped per user and conversation under the configured root" do
    expected = Rails.application.config.x.agent.root
                    .join("u#{@user.id}", "c#{@conversation.id}", "sessions")
    assert_equal expected, Agent::Workspace.for(@conversation).session_dir
  end

  test "session_dir lives under the configured agent root, not tmp/cache" do
    dir = Agent::Workspace.for(@conversation).session_dir.to_s
    assert dir.start_with?(Rails.application.config.x.agent.root.to_s)
  end

  test "prepare! creates the session directory" do
    workspace = Agent::Workspace.for(@conversation)
    refute Dir.exist?(workspace.session_dir)

    workspace.prepare!
    assert Dir.exist?(workspace.session_dir)
  ensure
    FileUtils.rm_rf(Rails.application.config.x.agent.root.join("u#{@user.id}"))
  end
end
