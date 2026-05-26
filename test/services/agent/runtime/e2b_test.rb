require "test_helper"

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
    attr_accessor :exist_paths, :entries_by_dir, :read_responses

    def initialize
      @writes = {}
      @exist_paths = []
      @entries_by_dir = {}
      @read_responses = {}
    end

    def write(path, data)
      @writes[path] = data
    end

    def exists?(path)
      @exist_paths.include?(path)
    end

    def list(path, **)
      @entries_by_dir.fetch(path, [])
    end

    def read(path, format: "text", **)
      bytes = @read_responses.fetch(path)
      format == "bytes" ? bytes.b : bytes
    end
  end

  # Fake E2B sandbox tracking create / resume / pause / kill.
  class FakeSandbox
    attr_reader :commands, :files, :sandbox_id
    attr_reader :paused_count, :resume_timeouts

    def initialize(sandbox_id: "sbx-fake", on_pause: nil, on_resume: nil)
      @commands = FakeCommands.new
      @files = FakeFiles.new
      @sandbox_id = sandbox_id
      @paused_count = 0
      @resume_timeouts = []
      @killed = false
      @on_pause = on_pause
      @on_resume = on_resume
    end

    def pause
      @on_pause&.call(self)
      @paused_count += 1
    end

    def resume(timeout: nil)
      @on_resume&.call(self)
      @resume_timeouts << timeout
    end

    def kill
      @killed = true
    end

    def killed?
      @killed
    end
  end

  def fake_session
    session = Object.new
    def session.close = nil
    session
  end

  # Stub E2B::Sandbox.create / .connect and PiAgent.session for the block.
  # `on_connect` is invoked with the sandbox_id requested.
  def with_e2b(create: nil, connect: nil, session: fake_session, on_connect: nil)
    create_original  = E2B::Sandbox.method(:create)
    connect_original = E2B::Sandbox.method(:connect)
    session_original = PiAgent.method(:session)
    E2B::Sandbox.define_singleton_method(:create)  { |**| create } if create
    E2B::Sandbox.define_singleton_method(:connect) { |id, **| on_connect&.call(id); connect } if connect
    PiAgent.define_singleton_method(:session) { |*, **| session }
    yield
  ensure
    E2B::Sandbox.define_singleton_method(:create,  create_original)
    E2B::Sandbox.define_singleton_method(:connect, connect_original)
    PiAgent.define_singleton_method(:session, session_original)
  end

  test "session_dir is the in-sandbox session path" do
    assert_equal Agent::Runtime::E2b::SESSION_DIR, @runtime.session_dir.to_s
  end

  test "first turn creates a sandbox, pauses it, and records the id on the conversation" do
    sandbox = FakeSandbox.new(sandbox_id: "sbx-new")

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_equal 1, sandbox.paused_count, "sandbox paused at end of turn"
    refute sandbox.killed?, "sandbox not killed — the next turn will resume it"
    assert_equal "sbx-new", @conversation.reload.e2b_sandbox_id
  end

  test "subsequent turns resume the stored sandbox, do not create a fresh one" do
    @conversation.update_column(:e2b_sandbox_id, "sbx-existing")
    sandbox = FakeSandbox.new(sandbox_id: "sbx-existing")
    connected_with = nil

    with_e2b(connect: sandbox, on_connect: ->(id) { connected_with = id }) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_equal "sbx-existing", connected_with
    assert_equal [ Agent::Runtime::E2b::SANDBOX_TIMEOUT ], sandbox.resume_timeouts,
                 "resumed with the runtime's timeout"
    assert_equal 1, sandbox.paused_count, "paused again at end of turn"
    assert_equal "sbx-existing", @conversation.reload.e2b_sandbox_id,
                 "id unchanged when same sandbox is reused"
  end

  test "a missing stored sandbox falls back to fresh provision and clears the stale id" do
    @conversation.update_column(:e2b_sandbox_id, "sbx-gone")
    fresh_sandbox = FakeSandbox.new(sandbox_id: "sbx-replacement")

    # E2B::Sandbox.connect raises NotFoundError when the id is gone
    # (evicted, killed externally, paused-state expired).
    with_stub(E2B::Sandbox, :connect, ->(_id, **_) { raise E2B::NotFoundError, "no such sandbox" }) do
      with_e2b(create: fresh_sandbox) do
        @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
      end
    end

    assert_equal "sbx-replacement", @conversation.reload.e2b_sandbox_id,
                 "the new sandbox's id replaces the stale one"
    assert_equal 1, fresh_sandbox.paused_count
  end

  test "pause failure best-effort kills the sandbox and clears the id" do
    # If pause fails the VM might still be alive — left as an orphan it
    # would leak (no auto-cleanup on E2B), so we kill and clear, letting
    # the next turn provision fresh.
    sandbox = FakeSandbox.new(
      sandbox_id: "sbx-pause-fail",
      on_pause: ->(_s) { raise E2B::E2BError, "pause http 500" }
    )

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert sandbox.killed?, "fallback to kill when pause fails"
    assert_nil @conversation.reload.e2b_sandbox_id, "stale id cleared"
  end

  test "uploads the app's pi extensions into the sandbox each turn" do
    sandbox = FakeSandbox.new

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    staged = sandbox.files.writes.keys.grep(%r{\A#{Agent::Runtime::E2b::EXTENSIONS_DIR}/})
    assert staged.any? { |path| path.end_with?("/web-tools.ts") },
           "web-tools extension uploaded into the sandbox"
  end

  test "extension_paths point at the uploaded extensions inside the sandbox" do
    paths = @runtime.extension_paths.map(&:to_s)

    assert_includes paths, "#{Agent::Runtime::E2b::EXTENSIONS_DIR}/web-tools.ts"
  end

  test "projects the conversation's uploaded files into the sandbox uploads dir" do
    sandbox = FakeSandbox.new
    message = @conversation.messages.create!(role: :user, content: "hi", streaming_status: :done)
    message.files.attach(io: StringIO.new("file contents"), filename: "notes.txt", content_type: "text/plain")

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    staged = "#{Agent::Runtime::E2b::WORKSPACE_DIR}/uploads/notes.txt"
    assert_equal "file contents", sandbox.files.writes[staged]
  end

  test "runtime_info reports the runtime name and the sandbox id" do
    sandbox = FakeSandbox.new(sandbox_id: "sbx-99")

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_equal({ "runtime" => "e2b", "sandbox_id" => "sbx-99" }, @runtime.runtime_info)
  end

  test "collects artifacts from the sandbox before the pause" do
    art_path = "#{Agent::Runtime::E2b::ARTIFACTS_DIR}/report.csv"
    paused_with_artifacts = nil

    sandbox = FakeSandbox.new(
      on_pause: ->(_s) { paused_with_artifacts = @runtime.artifacts.map { |a| a[:filename] } }
    )
    sandbox.files.exist_paths << Agent::Runtime::E2b::ARTIFACTS_DIR
    sandbox.files.entries_by_dir[Agent::Runtime::E2b::ARTIFACTS_DIR] = [
      E2B::Models::EntryInfo.new(
        name: "report.csv", type: E2B::Models::FileType::FILE,
        path: art_path, modified_time: Time.now + 5
      )
    ]
    sandbox.files.read_responses[art_path] = "a,b\n1,2\n"

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_equal [ "report.csv" ], paused_with_artifacts,
                 "artifacts collected before pause — a paused sandbox is unreachable"
    assert_equal "a,b\n1,2\n", @runtime.artifacts.first[:io].read
  end

  test "skips artifacts whose modified_time predates the turn" do
    art_path = "#{Agent::Runtime::E2b::ARTIFACTS_DIR}/old.csv"
    sandbox = FakeSandbox.new
    sandbox.files.exist_paths << Agent::Runtime::E2b::ARTIFACTS_DIR
    sandbox.files.entries_by_dir[Agent::Runtime::E2b::ARTIFACTS_DIR] = [
      E2B::Models::EntryInfo.new(
        name: "old.csv", type: E2B::Models::FileType::FILE,
        path: art_path, modified_time: Time.now - 3600
      )
    ]
    sandbox.files.read_responses[art_path] = "stale"

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_empty @runtime.artifacts
  end

  test "skips artifacts above the size cap" do
    big_path = "#{Agent::Runtime::E2b::ARTIFACTS_DIR}/huge.bin"
    ok_path = "#{Agent::Runtime::E2b::ARTIFACTS_DIR}/ok.csv"
    sandbox = FakeSandbox.new
    sandbox.files.exist_paths << Agent::Runtime::E2b::ARTIFACTS_DIR
    sandbox.files.entries_by_dir[Agent::Runtime::E2b::ARTIFACTS_DIR] = [
      E2B::Models::EntryInfo.new(name: "huge.bin", type: E2B::Models::FileType::FILE,
                                 path: big_path, size: 11.megabytes, modified_time: Time.now + 5),
      E2B::Models::EntryInfo.new(name: "ok.csv", type: E2B::Models::FileType::FILE,
                                 path: ok_path, size: 12, modified_time: Time.now + 5)
    ]
    sandbox.files.read_responses[ok_path] = "a,b\n1,2\n"

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_equal [ "ok.csv" ], @runtime.artifacts.map { |a| a[:filename] }
  end

  test "preserves the subdirectory in the artifact filename" do
    art_path = "#{Agent::Runtime::E2b::ARTIFACTS_DIR}/reports/q4.csv"
    sandbox = FakeSandbox.new
    sandbox.files.exist_paths << Agent::Runtime::E2b::ARTIFACTS_DIR
    sandbox.files.entries_by_dir[Agent::Runtime::E2b::ARTIFACTS_DIR] = [
      E2B::Models::EntryInfo.new(name: "reports", type: E2B::Models::FileType::DIRECTORY,
                                 path: "#{Agent::Runtime::E2b::ARTIFACTS_DIR}/reports",
                                 modified_time: Time.now + 5)
    ]
    sandbox.files.entries_by_dir["#{Agent::Runtime::E2b::ARTIFACTS_DIR}/reports"] = [
      E2B::Models::EntryInfo.new(name: "q4.csv", type: E2B::Models::FileType::FILE,
                                 path: art_path, size: 8, modified_time: Time.now + 5)
    ]
    sandbox.files.read_responses[art_path] = "csv data"

    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_equal [ "reports/q4.csv" ], @runtime.artifacts.map { |a| a[:filename] }
  end

  test "no-op when the artifacts dir was never created" do
    sandbox = FakeSandbox.new
    with_e2b(create: sandbox) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_empty @runtime.artifacts
  end

  test ".kill_sandbox swallows NotFoundError so eviction is idempotent" do
    with_stub(E2B::Sandbox, :kill, ->(_id, **_) { raise E2B::NotFoundError, "already gone" }) do
      assert_nothing_raised { Agent::Runtime::E2b.kill_sandbox("sbx-doesnt-exist") }
    end
  end

  test ".kill_sandbox is a no-op when the id is blank" do
    # Callers (Conversation#before_destroy, EvictPausedSandboxesJob) may
    # invoke with nil; an HTTP call against a nil id would 404 and log
    # noise pointlessly.
    called = false
    with_stub(E2B::Sandbox, :kill, ->(_id, **_) { called = true }) do
      Agent::Runtime::E2b.kill_sandbox(nil)
      Agent::Runtime::E2b.kill_sandbox("")
    end
    refute called
  end
end
