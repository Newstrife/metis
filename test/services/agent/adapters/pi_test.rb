require "test_helper"

class Agent::Adapters::PiTest < ActiveSupport::TestCase
  # Stub `pi --mode rpc`: on a prompt, acks then streams one assistant
  # message (two text deltas) and ends. Single-quoted heredoc so the
  # stub's own \n escapes survive to the child process verbatim.
  PROMPT_STUB = <<~'RUBY'
    require "json"
    $stdout.sync = true
    def emit(obj) = $stdout.write(JSON.generate(obj) + "\n")

    $stdin.each_line do |line|
      msg = JSON.parse(line)
      case msg["type"]
      when "prompt"
        emit({ "id" => msg["id"], "type" => "response", "command" => "prompt", "success" => true })
        emit({ "type" => "agent_start" })
        emit({ "type" => "message_start", "message" => { "id" => "m1", "role" => "assistant" } })
        emit({ "type" => "message_update", "message" => { "id" => "m1" },
               "assistantMessageEvent" => { "type" => "text_delta", "delta" => "Hi" } })
        emit({ "type" => "message_update", "message" => { "id" => "m1" },
               "assistantMessageEvent" => { "type" => "text_delta", "delta" => " there" } })
        emit({ "type" => "message_end", "message" => { "id" => "m1", "content" => "Hi there" } })
        emit({ "type" => "turn_end" })
        emit({ "type" => "agent_end", "messages" => [] })
      when "get_session_stats"
        emit({ "id" => msg["id"], "type" => "response", "command" => "get_session_stats",
               "success" => true, "data" => { "sessionId" => "stub-session-1" } })
      end
    end
  RUBY

  def adapter
    Agent::Adapters::Pi.new(conversation: Conversation.new(backend: :pi))
  end

  def pi_event(hash)
    PiAgent::Event.new(hash)
  end

  def create_conversation(**attrs)
    user = User.create!(email: "pi-#{SecureRandom.hex(4)}@example.com", password: "password123")
    user.conversations.create!({ backend: :pi }.merge(attrs))
  end

  # --- translation ---------------------------------------------------

  test "translates message_start" do
    ui = adapter.translate(pi_event("type" => "message_start",
                                    "message" => { "id" => "m1", "role" => "assistant" }))
    assert_equal :message_started, ui.type
    assert_equal "m1", ui[:id]
    assert_equal "assistant", ui[:role]
  end

  test "translates a text_delta message_update" do
    ui = adapter.translate(pi_event("type" => "message_update", "message" => { "id" => "m1" },
                                    "assistantMessageEvent" => { "type" => "text_delta", "delta" => "hello" }))
    assert_equal :text_delta, ui.type
    assert_equal "hello", ui[:delta]
  end

  test "translates a thinking_delta message_update to reasoning_delta" do
    ui = adapter.translate(pi_event("type" => "message_update",
                                    "assistantMessageEvent" => { "type" => "thinking_delta", "delta" => "hmm" }))
    assert_equal :reasoning_delta, ui.type
    assert_equal "hmm", ui[:delta]
  end

  test "translates an error message_update" do
    ui = adapter.translate(pi_event("type" => "message_update",
                                    "assistantMessageEvent" => { "type" => "error", "reason" => "error",
                                                                  "error" => "model failed" }))
    assert_equal :error, ui.type
    assert_equal "model failed", ui[:message]
  end

  test "translates message_end with array content" do
    ui = adapter.translate(pi_event("type" => "message_end",
                                    "message" => { "id" => "m1",
                                                   "content" => [ { "type" => "text", "text" => "final answer" } ] }))
    assert_equal :message_finished, ui.type
    assert_equal "final answer", ui[:content]
  end

  test "translates tool_execution_start" do
    ui = adapter.translate(pi_event("type" => "tool_execution_start", "toolCallId" => "call_1",
                                    "toolName" => "bash", "args" => { "command" => "ls" }))
    assert_equal :tool_call_started, ui.type
    assert_equal "call_1", ui[:tool_call_id]
    assert_equal "bash", ui[:name]
    assert_equal({ "command" => "ls" }, ui[:args])
  end

  test "translates tool_execution_update progress" do
    ui = adapter.translate(pi_event("type" => "tool_execution_update", "toolCallId" => "call_1",
                                    "partialResult" => { "content" => [ { "type" => "text", "text" => "partial" } ] }))
    assert_equal :tool_call_progress, ui.type
    assert_equal "call_1", ui[:tool_call_id]
    assert_equal "partial", ui[:output]
  end

  test "translates tool_execution_end with error flag" do
    ui = adapter.translate(pi_event("type" => "tool_execution_end", "toolCallId" => "call_1",
                                    "result" => { "content" => [ { "type" => "text", "text" => "boom" } ] },
                                    "isError" => true))
    assert_equal :tool_call_finished, ui.type
    assert_equal "boom", ui[:output]
    assert_equal true, ui[:is_error]
  end

  test "translates agent_end to a terminal turn_finished" do
    ui = adapter.translate(pi_event("type" => "agent_end", "messages" => []))
    assert_equal :turn_finished, ui.type
    assert ui.terminal?
  end

  test "translates extension_error" do
    ui = adapter.translate(pi_event("type" => "extension_error", "error" => "ext blew up"))
    assert_equal :error, ui.type
    assert_equal "ext blew up", ui[:message]
  end

  test "drops events the UI does not render" do
    assert_nil adapter.translate(pi_event("type" => "turn_start"))
    assert_nil adapter.translate(pi_event("type" => "agent_start"))
    assert_nil adapter.translate(pi_event("type" => "queue_update"))
  end

  test "preserves the native event payload on native_ref" do
    raw = { "type" => "agent_end", "messages" => [] }
    assert_equal raw, adapter.translate(pi_event(raw)).native_ref
  end

  # --- streaming -----------------------------------------------------

  test "stream translates a full pi prompt run into UiEvents" do
    client = PiAgent::Client.new(bin: "ruby", args: [ "-e", PROMPT_STUB ])
    session = PiAgent::Session.new(client.start)
    streaming_adapter = Agent::Adapters::Pi.new(conversation: Conversation.new(backend: :pi), session: session)

    events = []
    streaming_adapter.stream("hi") { |event| events << event }

    assert_equal %i[message_started text_delta text_delta message_finished turn_finished],
                 events.map(&:type)
    assert_equal "Hi", events[1][:delta]
    assert_equal " there", events[2][:delta]
    assert events.last.terminal?
  end

  test "stream captures pi's session id" do
    client = PiAgent::Client.new(bin: "ruby", args: [ "-e", PROMPT_STUB ])
    session = PiAgent::Session.new(client.start)
    streaming_adapter = Agent::Adapters::Pi.new(conversation: Conversation.new(backend: :pi), session: session)

    streaming_adapter.stream("hi") { |_event| nil }

    assert_equal "stub-session-1", streaming_adapter.native_session_id
  end

  # --- argument building ---------------------------------------------

  test "pi_args points at the workspace session directory" do
    conversation = create_conversation
    args = Agent::Adapters::Pi.new(conversation: conversation).pi_args

    assert_includes args, "--mode"
    assert_includes args, "rpc"
    dir = args[args.index("--session-dir") + 1]
    assert_match %r{/u#{conversation.user_id}/c#{conversation.id}/sessions\z}, dir
  end

  test "pi_args omits --continue for a fresh conversation" do
    args = Agent::Adapters::Pi.new(conversation: create_conversation).pi_args
    refute_includes args, "--continue"
  end

  test "pi_args includes --continue once a pi session exists" do
    conversation = create_conversation(backend_session_id: "sess-abc")
    args = Agent::Adapters::Pi.new(conversation: conversation).pi_args
    assert_includes args, "--continue"
  end

  test "pi_args carries credential flags from settings and the stored key" do
    conversation = create_conversation(
      settings: { "model" => "anthropic/claude-sonnet-4-5", "provider" => "anthropic" }
    )
    conversation.user.api_keys.create!(provider: "anthropic", key: "sk-test")
    args = Agent::Adapters::Pi.new(conversation: conversation).pi_args

    assert_equal "anthropic/claude-sonnet-4-5", args[args.index("--model") + 1]
    assert_equal "anthropic", args[args.index("--provider") + 1]
    assert_equal "sk-test", args[args.index("--api-key") + 1]
  end

  test "pi_args omits --api-key when no key is stored for the provider" do
    conversation = create_conversation(settings: { "provider" => "anthropic" })
    args = Agent::Adapters::Pi.new(conversation: conversation).pi_args

    assert_includes args, "--provider"
    refute_includes args, "--api-key"
  end
end
