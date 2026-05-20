require "test_helper"

class ChatJobTest < ActiveSupport::TestCase
  # Fake adapter that replays a canned Agent::UiEvent stream.
  class FakeAdapter
    attr_reader :native_session_id

    def initialize(events, native_session_id: nil)
      @events = events
      @native_session_id = native_session_id
    end

    def stream(_input)
      @events.each { |event| yield event }
    end
  end

  setup do
    @user = User.create!(email: "job@example.com", password: "password123")
    @conversation = @user.conversations.create!(backend: :pi, title: "Job test")
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

  def run_with(events, native_session_id: nil)
    with_adapter(FakeAdapter.new(events, native_session_id: native_session_id)) do
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

  test "marks the message errored for an unsupported backend" do
    @conversation.update!(backend: :claude_code)
    ChatJob.perform_now(@conversation.id, @user_message.id, @assistant_message.id)
    assert @assistant_message.reload.errored?
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
end
