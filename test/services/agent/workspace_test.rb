require "test_helper"

class Agent::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "ws@example.com", password: "password123")
    @conversation = @user.conversations.create!
  end

  teardown do
    [ Agent::Workspace::SCRATCH_ROOT, Agent::Workspace::PERSISTENT_ROOT ].each do |root|
      FileUtils.rm_rf(root.join("u#{@user.id}"))
    end
  end

  test "scratch and persistent resolve to different roots" do
    assert_includes Agent::Workspace.scratch(@conversation).scope_dir.to_s, "tmp/agent"
    assert_includes Agent::Workspace.persistent(@conversation).scope_dir.to_s, "storage/agent"
  end

  test "scopes the session, workspace, and uploads dirs per user and conversation" do
    workspace = Agent::Workspace.scratch(@conversation)
    scope = Agent::Workspace::SCRATCH_ROOT.join("u#{@user.id}", "c#{@conversation.id}")

    assert_equal scope, workspace.scope_dir
    assert_equal scope.join("sessions"), workspace.session_dir
    assert_equal scope.join("workspace"), workspace.workspace_dir
    assert_equal scope.join("workspace", "uploads"), workspace.uploads_dir
  end

  test "ensure! creates the scope directories, leaving existing content" do
    workspace = Agent::Workspace.scratch(@conversation)
    workspace.ensure!
    File.write(workspace.workspace_dir.join("keep.rb"), "code")

    workspace.ensure!
    assert Dir.exist?(workspace.session_dir)
    assert Dir.exist?(workspace.uploads_dir)
    assert_equal "code", File.read(workspace.workspace_dir.join("keep.rb")), "existing content kept"
  end

  test "reset! discards stale scratch from a previous run" do
    workspace = Agent::Workspace.scratch(@conversation)
    workspace.ensure!
    File.write(workspace.workspace_dir.join("stale.rb"), "old")

    workspace.reset!
    assert Dir.exist?(workspace.workspace_dir)
    refute File.exist?(workspace.workspace_dir.join("stale.rb"))
  end

  # An upload double whose filename is hostile — Active Storage already
  # sanitizes path separators, so a crafted name has to be injected here.
  class CraftedUpload
    def initialize(name, content)
      @name = name
      @content = content
    end

    def filename = @name

    def open
      yield StringIO.new(@content)
    end
  end

  test "stage_uploads basenames the filename so a crafted name cannot escape" do
    workspace = Agent::Workspace.scratch(@conversation)
    workspace.ensure!

    workspace.stage_uploads([ CraftedUpload.new("../escape.txt", "data") ])

    assert_equal "data", File.read(workspace.uploads_dir.join("escape.txt"))
    refute File.exist?(workspace.scope_dir.join("escape.txt")), "the crafted name did not escape"
  end

  test "stage_mcp_config writes .mcp.json into the workspace root" do
    workspace = Agent::Workspace.scratch(@conversation)
    workspace.ensure!

    workspace.stage_mcp_config(%({"mcpServers":{}}))

    assert_equal %({"mcpServers":{}}), File.read(workspace.workspace_dir.join(".mcp.json"))
  end

  test "stage_identity writes AGENTS.md into the workspace root" do
    workspace = Agent::Workspace.scratch(@conversation)
    workspace.ensure!

    workspace.stage_identity("# Hello, pi")

    assert_equal "# Hello, pi", File.read(workspace.workspace_dir.join("AGENTS.md"))
  end
end
