require "test_helper"

class Agent::Runtime::E2bTransportTest < ActiveSupport::TestCase
  # Fake E2B CommandHandle: replays canned (stdout, stderr, pty) chunks
  # and records stdin writes.
  class FakeHandle
    attr_reader :stdin_writes

    def initialize(chunks)
      @chunks = chunks
      @stdin_writes = []
      @killed = false
    end

    def each
      @chunks.each { |stdout, stderr, pty| yield(stdout, stderr, pty) }
    end

    def send_stdin(data)
      @stdin_writes << data
    end

    def kill
      @killed = true
    end

    def killed?
      @killed
    end
  end

  class FakeCommands
    def initialize(handle)
      @handle = handle
    end

    def run(*_args, **_kwargs)
      @handle
    end
  end

  class FakeSandbox
    def initialize(handle)
      @handle = handle
    end

    def commands
      FakeCommands.new(@handle)
    end
  end

  def build_transport(chunks, on_message: nil, on_stderr: nil)
    handle = FakeHandle.new(chunks)
    transport = Agent::Runtime::E2bTransport.new(
      sandbox: FakeSandbox.new(handle), command: "pi --mode rpc",
      on_message: on_message, on_stderr: on_stderr
    )
    [ transport, handle ]
  end

  test "parses JSON messages from stdout chunks" do
    received = Queue.new
    transport, = build_transport(
      [ [ %({"type":"a"}\n), nil, nil ], [ %({"type":"b","x":1}\n), nil, nil ] ],
      on_message: ->(msg) { received << msg }
    )
    transport.start

    assert_equal({ "type" => "a" }, received.pop(timeout: 2))
    assert_equal({ "type" => "b", "x" => 1 }, received.pop(timeout: 2))
  ensure
    transport&.close
  end

  test "reframes a JSON message split across chunks" do
    received = Queue.new
    transport, = build_transport(
      [ [ %({"type":), nil, nil ], [ %("split"}\n), nil, nil ] ],
      on_message: ->(msg) { received << msg }
    )
    transport.start

    assert_equal({ "type" => "split" }, received.pop(timeout: 2))
  ensure
    transport&.close
  end

  test "write sends a JSON line to the command's stdin" do
    transport, handle = build_transport([])
    transport.start
    transport.write({ "x" => 1 })

    assert_equal [ %({"x":1}\n) ], handle.stdin_writes
  ensure
    transport&.close
  end

  test "forwards stderr chunks as lines" do
    received = Queue.new
    transport, = build_transport(
      [ [ nil, "boom\n", nil ] ],
      on_stderr: ->(line) { received << line }
    )
    transport.start

    assert_equal "boom", received.pop(timeout: 2)
  ensure
    transport&.close
  end

  test "close kills the command and rejects further writes" do
    transport, handle = build_transport([])
    transport.start
    transport.close

    assert handle.killed?
    assert_raises(PiAgent::ProtocolError) { transport.write({ "x" => 1 }) }
  end
end
