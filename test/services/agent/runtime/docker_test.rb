require "test_helper"

class Agent::Runtime::DockerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "rt-docker@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @runtime = Agent::Runtime::Docker.new(conversation: @conversation)
    @workspace = Agent::Workspace.for(@conversation)
    # Never shell out to `docker` for teardown in a unit test.
    @runtime.define_singleton_method(:remove_container) { nil }
  end

  teardown do
    FileUtils.rm_rf(Agent::Workspace::ROOT.join("u#{@user.id}"))
  end

  # Swap PiAgent.session so #run never spawns `docker run`.
  def with_pi_session(session)
    original = PiAgent.method(:session)
    PiAgent.define_singleton_method(:session) { |*, **| session }
    yield
  ensure
    PiAgent.define_singleton_method(:session, original)
  end

  def fake_session
    session = Object.new
    def session.closed? = @closed
    def session.close = (@closed = true)
    session
  end

  test "session_dir is the in-container session path" do
    assert_equal Pathname.new("/metis/sessions"), @runtime.session_dir
  end

  test "extension_paths point inside the read-only extensions mount" do
    paths = @runtime.extension_paths.map(&:to_s)
    assert_includes paths, "/metis-extensions/web-tools/index.ts"
  end

  test "runtime_info names the docker runtime and its container" do
    info = @runtime.runtime_info
    assert_equal "docker", info["runtime"]
    assert_match(/\Ametis-c#{@conversation.id}-/, info["container"])
  end

  test "docker_args wraps pi in a disposable, mounted, hardened container" do
    args = @runtime.send(:docker_args, [ "--mode", "rpc" ])

    assert_equal "run", args.first
    assert_includes args, "--rm"
    assert_includes args, "-i"
    assert_includes args, "--cap-drop"
    assert_includes args, "#{@workspace.scope_dir}:/metis"
    assert_includes args, Rails.application.config.x.agent.docker_image
    assert_equal [ "pi", "--mode", "rpc" ], args.last(3)
  end

  test "run provisions the workspace, yields the session, and archives after" do
    session = fake_session
    yielded = nil

    with_pi_session(session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) do |s|
        yielded = s
        assert Dir.exist?(@workspace.workspace_dir), "workspace provisioned"
      end
    end

    assert_equal session, yielded
    assert session.closed?, "session closed by the runtime"
    assert @conversation.pi_session_archive.attached?, "scope archived"
  end
end
