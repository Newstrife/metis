require "test_helper"

class ChatJobTest < ActiveSupport::TestCase
  # Fake adapter that replays a canned Agent::UiEvent stream.
  class FakeAdapter
    attr_reader :native_session_id, :token_totals, :context_usage, :model_info, :runtime_info

    def initialize(events, native_session_id: nil, token_totals: nil, context_usage: nil,
                   model_info: nil, runtime_info: nil)
      @events = events
      @native_session_id = native_session_id
      @token_totals = token_totals
      @context_usage = context_usage
      @model_info = model_info
      @runtime_info = runtime_info
    end

    def stream(_input, images: [], files: [])
      @events.each { |event| yield event }
    end
  end

  setup do
    @user = User.create!(email: "job@example.com", password: "password123")
    @conversation = @user.conversations.create!(title: "Job test")
    @user_message = @conversation.messages.create!(role: :user, content: "hi", streaming_status: :done)
    @assistant_message = @conversation.messages.create!(role: :assistant, content: "", streaming_status: :pending)
  end

  # Swap Agent::Adapters.for for the duration of the block.
  def with_adapter(adapter)
    original = Agent::Adapters.method(:for)
    Agent::Adapters.define_singleton_method(:for) { |*, **| adapter }
    yield
  ensure
    Agent::Adapters.define_singleton_method(:for, original)
  end

  def run_with(events, **adapter_opts)
    with_adapter(FakeAdapter.new(events, **adapter_opts)) do
      ChatJob.perform_now(@conversation.id, @user_message.id, @assistant_message.id)
    end
  end

  test "accumulates text deltas and marks the assistant message done" do
    run_with([
               Agent::UiEvent.new(:message_started, data: { role: "assistant" }),
               Agent::UiEvent.new(:text_delta, data: { delta: "Hello" }),
               Agent::UiEvent.new(:text_delta, data: { delta: " world" }),
               Agent::UiEvent.new(:message_finished, data: { content: "Hello world" }),
               Agent::UiEvent.new(:turn_finished)
             ])

    @assistant_message.reload
    assert_equal "Hello world", @assistant_message.content
    assert @assistant_message.done?
  end

  test "persists the reasoning log and tool calls so they survive a refresh" do
    run_with([
               Agent::UiEvent.new(:reasoning_delta, data: { delta: "thinking " }),
               Agent::UiEvent.new(:reasoning_delta, data: { delta: "hard" }),
               Agent::UiEvent.new(:tool_call_started,
                                  data: { tool_call_id: "t1", name: "bash", args: { "command" => "ls" } }),
               Agent::UiEvent.new(:tool_call_finished,
                                  data: { tool_call_id: "t1", output: "file.txt", is_error: false }),
               Agent::UiEvent.new(:turn_finished)
             ])

    @assistant_message.reload
    assert_equal "thinking hard", @assistant_message.reasoning

    call = @assistant_message.tool_calls.sole
    assert_equal "bash", call["name"]
    assert_equal({ "command" => "ls" }, call["args"])
    assert_equal "file.txt", call["output"]
    assert_equal "done", call["status"]
  end

  test "marks the message errored when an error event arrives" do
    run_with([
               Agent::UiEvent.new(:text_delta, data: { delta: "partial" }),
               Agent::UiEvent.new(:error, data: { message: "boom" }),
               Agent::UiEvent.new(:turn_finished)
             ])

    assert @assistant_message.reload.errored?
  end

  test "persists pi's session id to the conversation" do
    run_with([ Agent::UiEvent.new(:text_delta, data: { delta: "hi" }),
              Agent::UiEvent.new(:turn_finished) ],
             native_session_id: "sess-xyz")

    assert_equal "sess-xyz", @conversation.reload.backend_session_id
  end

  test "leaves backend_session_id unset when the adapter reports none" do
    run_with([ Agent::UiEvent.new(:turn_finished) ])
    assert_nil @conversation.reload.backend_session_id
  end

  test "touches the conversation after a successful run" do
    before = @conversation.updated_at
    travel 1.second do
      run_with([ Agent::UiEvent.new(:text_delta, data: { delta: "x" }),
                Agent::UiEvent.new(:turn_finished) ])
    end
    assert_operator @conversation.reload.updated_at, :>, before
  end

  test "records this turn's token usage on the assistant message" do
    run_with([ Agent::UiEvent.new(:turn_finished) ],
             token_totals: { "input" => 100, "output" => 40, "cacheRead" => 10 })

    @assistant_message.reload
    assert_equal 100, @assistant_message.input_tokens
    assert_equal 40, @assistant_message.output_tokens
    assert_equal 10, @assistant_message.cache_read_tokens
  end

  test "token usage is this turn's rise over earlier turns' cumulative totals" do
    @conversation.messages.create!(
      role: :assistant, content: "earlier", streaming_status: :done,
      input_tokens: 70, output_tokens: 25, cache_read_tokens: 5
    )
    run_with([ Agent::UiEvent.new(:turn_finished) ],
             token_totals: { "input" => 100, "output" => 40, "cacheRead" => 10 })

    @assistant_message.reload
    assert_equal 30, @assistant_message.input_tokens
    assert_equal 15, @assistant_message.output_tokens
    assert_equal 5, @assistant_message.cache_read_tokens
  end

  test "stores the context-window usage on the conversation" do
    run_with([ Agent::UiEvent.new(:turn_finished) ],
             context_usage: { "tokens" => 195, "contextWindow" => 272000, "percent" => 0.07 })

    assert_equal 272000, @conversation.reload.context_usage["contextWindow"]
  end

  test "stores the resolved model on the conversation" do
    run_with([ Agent::UiEvent.new(:turn_finished) ],
             model_info: { "id" => "gpt-5.5", "name" => "GPT-5.5", "provider" => "openai-codex" })

    assert_equal "GPT-5.5", @conversation.reload.agent_model["name"]
    assert_equal "openai-codex", @conversation.agent_model["provider"]
  end

  test "marks the message errored when the adapter raises" do
    raiser = Object.new
    def raiser.stream(*)
      raise "pi crashed"
    end

    with_adapter(raiser) do
      ChatJob.perform_now(@conversation.id, @user_message.id, @assistant_message.id)
    end
    assert @assistant_message.reload.errored?
  end

  test "records where the turn ran on the conversation" do
    run_with([ Agent::UiEvent.new(:turn_finished) ],
             runtime_info: { "runtime" => "e2b", "sandbox_id" => "sbx-1" })

    assert_equal({ "runtime" => "e2b", "sandbox_id" => "sbx-1" }, @conversation.reload.runtime_state)
  end

  test "stamps finished_at so a completed turn has a duration" do
    @assistant_message.update!(started_at: 3.seconds.ago)
    run_with([ Agent::UiEvent.new(:turn_finished) ])

    @assistant_message.reload
    assert_not_nil @assistant_message.finished_at
    assert_operator @assistant_message.duration, :>, 0
  end

  test "stamps finished_at even when the turn fails" do
    raiser = Object.new
    def raiser.stream(*)
      raise "pi crashed"
    end

    with_adapter(raiser) do
      ChatJob.perform_now(@conversation.id, @user_message.id, @assistant_message.id)
    end
    assert_not_nil @assistant_message.reload.finished_at
  end
end
