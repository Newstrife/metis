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
      next unless msg["type"] == "prompt"

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
    end
  RUBY

  def adapter
    Agent::Adapters::Pi.new(conversation: Conversation.new(backend: :pi))
  end

  def pi_event(hash)
    PiAgent::Event.new(hash)
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
end
