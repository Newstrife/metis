require "test_helper"

class Agent::Runtime::LocalTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "rt@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @runtime = Agent::Runtime::Local.new(conversation: @conversation)
    @workspace = Agent::Workspace.persistent(@conversation)
  end

  teardown do
    FileUtils.rm_rf(Agent::Workspace::PERSISTENT_ROOT.join("u#{@user.id}"))
  end

  # Swap PiAgent.session so #run never spawns a real pi process.
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

  test "session_dir is the persistent workspace session directory" do
    assert_equal @workspace.session_dir, @runtime.session_dir
  end

  test "runtime_info names the local runtime" do
    assert_equal({ "runtime" => "local" }, @runtime.runtime_info)
  end

  test "extension_paths offers the repo's bundled pi extensions in place" do
    paths = @runtime.extension_paths.map(&:to_s)

    assert paths.any? { |path| path.end_with?(".pi/extensions/web-tools/index.ts") },
           "web-tools extension is offered to pi"
    assert paths.all? { |path| File.exist?(path) }, "extension files exist on this host"
  end

  test "run provisions the workspace and yields the session" do
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
  end

  test "run keeps the scope between turns and never archives" do
    with_pi_session(fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) do |_s|
        File.write(@workspace.workspace_dir.join("turn1.rb"), "code")
      end
    end

    seen_on_turn2 = nil
    with_pi_session(fake_session) do
      Agent::Runtime::Local.new(conversation: @conversation).run(pi_args: [ "--mode", "rpc" ]) do |_s|
        seen_on_turn2 = File.exist?(@workspace.workspace_dir.join("turn1.rb"))
      end
    end

    assert seen_on_turn2, "turn 1's workspace files are still there on turn 2 (pi-native persistence)"
    assert_not @conversation.reload.pi_session_archive.attached?, "Local does not archive"
  end

  test "run projects the conversation's uploaded files into uploads/" do
    message = @conversation.messages.create!(role: :user, content: "hi", streaming_status: :done)
    message.files.attach(io: StringIO.new("a,b\n1,2\n"), filename: "data.csv", content_type: "text/csv")
    staged = @workspace.uploads_dir.join("data.csv")

    with_pi_session(fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) do |_s|
        assert File.exist?(staged), "upload projected before the run"
      end
    end

    assert_equal "a,b\n1,2\n", File.read(staged)
  end

  test "run closes the session even when the block raises" do
    session = fake_session

    assert_raises(RuntimeError) do
      with_pi_session(session) do
        @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| raise "turn failed" }
      end
    end

    assert session.closed?
  end
end
