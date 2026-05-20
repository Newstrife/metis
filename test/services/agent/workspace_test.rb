require "test_helper"

class Agent::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "ws@example.com", password: "password123")
    @conversation = @user.conversations.create!(backend: :pi)
  end

  teardown do
    FileUtils.rm_rf(Agent::Workspace::ROOT.join("u#{@user.id}"))
  end

  test "scopes session_dir and workspace_dir per user and conversation" do
    scope = Agent::Workspace::ROOT.join("u#{@user.id}", "c#{@conversation.id}")
    workspace = Agent::Workspace.for(@conversation)

    assert_equal scope, workspace.scope_dir
    assert_equal scope.join("sessions"), workspace.session_dir
    assert_equal scope.join("workspace"), workspace.workspace_dir
  end

  test "prepare! creates both the session and workspace directories" do
    workspace = Agent::Workspace.for(@conversation)
    refute Dir.exist?(workspace.scope_dir)

    workspace.prepare!
    assert Dir.exist?(workspace.session_dir)
    assert Dir.exist?(workspace.workspace_dir)
  end

  test "prepare! discards stale scratch from a previous run" do
    workspace = Agent::Workspace.for(@conversation)
    workspace.prepare!
    File.write(workspace.session_dir.join("stale.jsonl"), "old")
    File.write(workspace.workspace_dir.join("stale.rb"), "old")

    workspace.prepare!
    refute File.exist?(workspace.session_dir.join("stale.jsonl"))
    refute File.exist?(workspace.workspace_dir.join("stale.rb"))
  end
end
