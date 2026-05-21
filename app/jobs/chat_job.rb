# Runs one agent turn: streams the backend adapter's UiEvents, broadcasts
# them to the conversation, and persists the assistant message.
class ChatJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, user_message_id, assistant_message_id)
    conversation = Conversation.find(conversation_id)
    user_message = Message.find(user_message_id)
    assistant_message = Message.find(assistant_message_id)
    broadcaster = ChatBroadcaster.new(conversation, assistant_message)

    run(conversation, user_message, assistant_message, broadcaster)
  rescue StandardError => e
    Rails.logger.error("ChatJob #{conversation_id} failed: #{e.class}: #{e.message}")
    fail_message(assistant_message, broadcaster, "The agent run failed.")
  end

  private

  def run(conversation, user_message, assistant_message, broadcaster)
    assistant_message.update!(streaming_status: :streaming)
    adapter = Agent::Adapters.for(conversation)
    text = +""
    reasoning = +""
    tools = {}
    errored = false

    adapter.stream(user_message.content,
                   images: user_message.images, files: user_message.files) do |event|
      case event.type
      when :text_delta      then text << event[:delta].to_s
      when :reasoning_delta then reasoning << event[:delta].to_s
      when :tool_call_started, :tool_call_progress, :tool_call_finished
        record_tool_call(tools, event)
      when :error           then errored = true
      end
      broadcaster.handle(event)
    end

    assistant_message.update!(
      content: text,
      reasoning: reasoning.presence,
      tool_calls: tools.values,
      streaming_status: errored ? :errored : :done,
      finished_at: Time.current,
      **turn_token_columns(conversation, adapter)
    )
    persist_session_id(conversation, adapter)
    persist_context_usage(conversation, adapter)
    persist_agent_model(conversation, adapter)
    persist_runtime(conversation, adapter)
    conversation.touch
    broadcaster.refresh_usage
    broadcaster.collapse_activity
  end

  # Accumulate one tool call across its started/progress/finished events,
  # keyed by id so progress and result land on the right entry.
  def record_tool_call(tools, event)
    call = (tools[event[:tool_call_id]] ||= { "tool_call_id" => event[:tool_call_id] })
    call["name"]     = event[:name]     if event.data.key?(:name)
    call["args"]     = event[:args]     if event.data.key?(:args)
    call["output"]   = event[:output]   if event.data.key?(:output)
    call["is_error"] = event[:is_error] if event.data.key?(:is_error)
    call["status"]   = event.type == :tool_call_finished ? "done" : "running"
  end

  # Record pi's session id so the next message resumes the same session.
  def persist_session_id(conversation, adapter)
    session_id = adapter.native_session_id
    return if session_id.blank? || session_id == conversation.backend_session_id

    conversation.update_column(:backend_session_id, session_id)
  end

  # pi reports cumulative session token counts; this turn's share is the
  # rise over what earlier messages already account for. Computed before
  # the assistant message's own tokens are written.
  def turn_token_columns(conversation, adapter)
    totals = adapter.token_totals
    return {} if totals.blank?

    {
      input_tokens:      turn_delta(totals["input"],     conversation.messages.sum(:input_tokens)),
      output_tokens:     turn_delta(totals["output"],    conversation.messages.sum(:output_tokens)),
      cache_read_tokens: turn_delta(totals["cacheRead"], conversation.messages.sum(:cache_read_tokens))
    }
  end

  def turn_delta(total, prior)
    [ total.to_i - prior.to_i, 0 ].max
  end

  # Store the latest context-window snapshot for the conversation header.
  def persist_context_usage(conversation, adapter)
    usage = adapter.context_usage
    return if usage.blank?

    conversation.update_column(:context_usage, usage)
  end

  # Store the model pi resolved for the conversation (it can change if a
  # model is switched mid-conversation).
  def persist_agent_model(conversation, adapter)
    model = adapter.model_info
    return if model.blank? || model == conversation.agent_model

    conversation.update_column(:agent_model, model)
  end

  # Record where the turn ran — the runtime name and, for E2B, the
  # sandbox id — on the conversation.
  def persist_runtime(conversation, adapter)
    info = adapter.runtime_info
    return if info.blank? || info == conversation.runtime_state

    conversation.update_column(:runtime_state, info)
  end

  def fail_message(assistant_message, broadcaster, message)
    return unless assistant_message

    assistant_message.update!(streaming_status: :errored, finished_at: Time.current)
    broadcaster&.fail(message)
  end
end
