require "test_helper"

class Agent::Runtime::LocalTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "rt@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @runtime = Agent::Runtime::Local.new(conversation: @conversation)
    @workspace = Agent::Workspace.for(@conversation)
  end

  teardown do
    FileUtils.rm_rf(Agent::Workspace::ROOT.join("u#{@user.id}"))
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

  # A stand-in for an uploaded file: responds to #filename and #open.
  class FakeUpload
    def initialize(name, content)
      @name = name
      @content = content
    end

    def filename = @name

    def open
      yield StringIO.new(@content)
    end
  end

  test "session_dir is the workspace session directory" do
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
        assert Dir.exist?(@workspace.session_dir), "session dir provisioned"
        assert Dir.exist?(@workspace.workspace_dir), "workspace dir provisioned"
      end
    end

    assert_equal session, yielded
  end

  test "run closes the session and archives the scope afterward" do
    session = fake_session

    with_pi_session(session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert session.closed?, "session was closed by the runtime"
    assert @conversation.pi_session_archive.attached?, "scope archived"
  end

  test "run closes and archives even when the block raises" do
    session = fake_session

    assert_raises(RuntimeError) do
      with_pi_session(session) do
        @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| raise "turn failed" }
      end
    end

    assert session.closed?
    assert @conversation.pi_session_archive.attached?
  end

  test "run stages uploaded files into the workspace before yielding" do
    staged = @workspace.workspace_dir.join("data.csv")

    with_pi_session(fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ],
                   files: [ FakeUpload.new("data.csv", "a,b\n1,2\n") ]) do |_s|
        assert File.exist?(staged), "file staged before the run"
      end
    end

    assert_equal "a,b\n1,2\n", File.read(staged)
  end

  test "run basenames staged filenames so a crafted name cannot escape the workspace" do
    with_pi_session(fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ],
                   files: [ FakeUpload.new("../escape.txt", "x") ]) do |_s|
        assert File.exist?(@workspace.workspace_dir.join("escape.txt"))
        assert_not File.exist?(@workspace.scope_dir.join("escape.txt"))
      end
    end
  end
end
