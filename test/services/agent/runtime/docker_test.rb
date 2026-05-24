require "test_helper"

class Agent::Runtime::DockerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "rt-docker@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @runtime = Agent::Runtime::Docker.new(conversation: @conversation)
    @workspace = Agent::Workspace.scratch(@conversation)
    # Never shell out to `docker` for teardown in a unit test.
    @runtime.define_singleton_method(:remove_container) { nil }
  end

  teardown do
    FileUtils.rm_rf(Agent::Workspace::SCRATCH_ROOT.join("u#{@user.id}"))
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

  test "docker_args forwards credential env vars with the bare-key form (no token in argv)" do
    # `--env NAME` (no value) tells docker to read NAME from the parent
    # process's env. PiAgent.session(env:) puts the value there. This
    # keeps the bearer out of argv where `ps` could see it.
    args = @runtime.send(:docker_args, [ "--mode", "rpc" ], env: { "GH_TOKEN" => "secret-bearer" })

    gh_index = args.each_index.find { |i| args[i] == "--env" && args[i + 1] == "GH_TOKEN" }
    assert gh_index, "expected --env GH_TOKEN in docker args"
    refute_includes args, "GH_TOKEN=secret-bearer", "bearer must not appear inline in argv"
    refute_includes args, "secret-bearer", "bearer must not appear inline in argv"
  end

  test "sandbox_env carries GH_TOKEN and git identity when the user has a covering GitHub grant" do
    @user.oauth_grants.create!(
      provider: "github", access_token: "live-bearer", refresh_token: "rt",
      expires_at: 1.hour.from_now, scopes: "user:email repo"
    )

    env = @runtime.sandbox_env

    assert_equal "live-bearer", env["GH_TOKEN"]
    assert_equal @user.email, env["GIT_AUTHOR_EMAIL"]
    assert_equal @user.email, env["GIT_COMMITTER_EMAIL"]
    assert_equal @user.email.split("@", 2).first, env["GIT_AUTHOR_NAME"]
  end

  test "sandbox_env is empty when the user has no covering GitHub grant" do
    assert_empty @runtime.sandbox_env

    # Sign-in scope only — McpConfig would drop the connector; sandbox_env
    # must also stay empty so the agent doesn't think GH_TOKEN is in env.
    @user.oauth_grants.create!(
      provider: "github", access_token: "live", refresh_token: "rt",
      expires_at: 1.hour.from_now, scopes: "user:email"
    )

    assert_empty @runtime.sandbox_env
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
