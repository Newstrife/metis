require "test_helper"

class Agent::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "ws@example.com", password: "password123")
    @conversation = @user.conversations.create!(backend: :pi)
  end

  teardown do
    FileUtils.rm_rf(Agent::Workspace::ROOT.join("u#{@user.id}"))
  end

  test "session_dir is scoped per user and conversation under tmp/agent" do
    expected = Agent::Workspace::ROOT.join("u#{@user.id}", "c#{@conversation.id}", "sessions")
    assert_equal expected, Agent::Workspace.for(@conversation).session_dir
  end

  test "prepare! creates the session directory" do
    workspace = Agent::Workspace.for(@conversation)
    refute Dir.exist?(workspace.session_dir)

    workspace.prepare!
    assert Dir.exist?(workspace.session_dir)
  end

  test "prepare! discards stale scratch from a previous run" do
    workspace = Agent::Workspace.for(@conversation)
    workspace.prepare!
    File.write(workspace.session_dir.join("stale.jsonl"), "old")

    workspace.prepare!
    assert Dir.exist?(workspace.session_dir)
    refute File.exist?(workspace.session_dir.join("stale.jsonl"))
  end
end
