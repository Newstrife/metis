require "test_helper"
require "tmpdir"

class Agent::Runtime::E2bTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "e2b@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @runtime = Agent::Runtime::E2b.new(conversation: @conversation)
  end

  class FakeCommands
    attr_reader :runs

    def initialize
      @runs = []
    end

    def run(cmd, **_kwargs)
      @runs << cmd
    end
  end

  class FakeFiles
    attr_reader :writes

    def initialize(read_bytes)
      @read_bytes = read_bytes
      @writes = {}
    end

    def write(path, data)
      @writes[path] = data
    end

    def read(_path, format: nil)
      @read_bytes
    end
  end

  # Fake E2B sandbox recording commands, file writes, and termination.
  class FakeSandbox
    attr_reader :commands, :files, :sandbox_id

    def initialize(read_bytes: "captured-archive-bytes", sandbox_id: "sbx-fake")
      @commands = FakeCommands.new
      @files = FakeFiles.new(read_bytes)
      @sandbox_id = sandbox_id
      @killed = false
    end

    def kill
      @killed = true
    end

    def killed?
      @killed
    end
  end

  # Upload double — responds to #filename and #download.
  FakeUpload = Struct.new(:filename, :bytes) do
    def download
      bytes
    end
  end

  def fake_session
    session = Object.new
    def session.close = nil
    session
  end

  # Stub E2B::Sandbox.create and PiAgent.session for the block.
  def with_e2b(sandbox:, session:)
    create_original = E2B::Sandbox.method(:create)
    session_original = PiAgent.method(:session)
    E2B::Sandbox.define_singleton_method(:create) { |**| sandbox }
    PiAgent.define_singleton_method(:session) { |*, **| session }
    yield
  ensure
    E2B::Sandbox.define_singleton_method(:create, create_original)
    PiAgent.define_singleton_method(:session, session_original)
  end

  test "session_dir is the in-sandbox session path" do
    assert_equal Agent::Runtime::E2b::SESSION_DIR, @runtime.session_dir.to_s
  end

  test "creates a sandbox, runs the turn, and kills the sandbox" do
    sandbox = FakeSandbox.new

    with_e2b(sandbox: sandbox, session: fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert sandbox.killed?, "sandbox terminated after the turn"
  end

  test "persists the scope to durable storage after the turn" do
    sandbox = FakeSandbox.new(read_bytes: "the-tarball")

    with_e2b(sandbox: sandbox, session: fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert @conversation.pi_session_archive.attached?
    assert_equal "the-tarball", @conversation.pi_session_archive.download
    assert_includes sandbox.commands.runs.join("\n"), "tar -czf"
  end

  test "does not hydrate on the first turn (no prior archive)" do
    sandbox = FakeSandbox.new

    with_e2b(sandbox: sandbox, session: fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    refute_includes sandbox.commands.runs.join("\n"), "tar -xzf"
  end

  test "hydrates the sandbox from a stored archive" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "marker"), "x")
      Agent::SessionArchive.store(@conversation, from: dir)
    end
    sandbox = FakeSandbox.new

    with_e2b(sandbox: sandbox, session: fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert sandbox.files.writes.key?(Agent::Runtime::E2b::REMOTE_ARCHIVE), "archive uploaded into the sandbox"
    assert_includes sandbox.commands.runs.join("\n"), "tar -xzf"
  end

  test "stages uploaded files into the sandbox workspace" do
    sandbox = FakeSandbox.new
    upload = FakeUpload.new("notes.txt", "file contents")

    with_e2b(sandbox: sandbox, session: fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ], files: [ upload ]) { |_s| nil }
    end

    staged = "#{Agent::Runtime::E2b::WORKSPACE_DIR}/notes.txt"
    assert_equal "file contents", sandbox.files.writes[staged]
  end

  test "runtime_info reports the runtime name and the run's sandbox id" do
    sandbox = FakeSandbox.new(sandbox_id: "sbx-99")

    with_e2b(sandbox: sandbox, session: fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_equal({ "runtime" => "e2b", "sandbox_id" => "sbx-99" }, @runtime.runtime_info)
  end
end
