# Maps Agent::UiEvent objects to Turbo Stream broadcasts on a
# conversation's stream. Owns the live DOM; ChatJob owns persistence.
class ChatBroadcaster
  include ActionView::RecordIdentifier

  def initialize(conversation, assistant_message)
    @conversation = conversation
    @message = assistant_message
    @text = +""
  end

  def handle(event)
    case event.type
    when :text_delta        then append_text(event[:delta])
    when :reasoning_delta   then append_reasoning(event[:delta])
    when :tool_call_started then start_tool(event)
    when :tool_call_progress, :tool_call_finished then update_tool(event)
    when :turn_finished     then finish
    when :error             then show_error(event[:message])
    end
  end

  # Called by ChatJob when the run fails before/outside the event stream.
  def fail(message)
    show_error(message)
    finish
  end

  private

  def base_id = dom_id(@message)

  # Accumulate the streamed text and re-render the whole body as Markdown.
  # An innerHTML update (not append) keeps partial Markdown — open code
  # fences, half-built tables — rendering correctly as more text arrives.
  def append_text(delta)
    return if delta.blank?

    @text << delta
    Turbo::StreamsChannel.broadcast_update_to(
      @conversation, target: "#{base_id}_body",
      html: ApplicationController.helpers.markdown(@text)
    )
  end

  def append_reasoning(delta)
    return if delta.blank?

    broadcast_append(target: "#{base_id}_reasoning", html: ERB::Util.html_escape(delta))
  end

  def start_tool(event)
    broadcast(:append, target: "#{base_id}_tools", partial: "messages/tool_call",
                       locals: tool_locals(event, status: :running))
  end

  def update_tool(event)
    status = event.type == :tool_call_finished ? :done : :running
    broadcast(:replace, target: "tool_#{event[:tool_call_id]}", partial: "messages/tool_call",
                        locals: tool_locals(event, status:))
  end

  def finish
    Turbo::StreamsChannel.broadcast_remove_to(@conversation, target: "#{base_id}_indicator")
  end

  # Append into the message card, not the body — the body's innerHTML is
  # replaced on every text delta, which would otherwise swallow the error.
  def show_error(message)
    broadcast(:append, target: base_id, partial: "messages/error",
                       locals: { message: message })
  end

  def tool_locals(event, status:)
    {
      tool_call_id: event[:tool_call_id],
      name: event[:name],
      args: event[:args],
      output: event[:output],
      is_error: event[:is_error],
      status: status
    }
  end

  def broadcast_append(target:, html:)
    Turbo::StreamsChannel.broadcast_append_to(@conversation, target: target, html: html)
  end

  def broadcast(action, target:, partial:, locals:)
    Turbo::StreamsChannel.public_send(
      "broadcast_#{action}_to", @conversation, target: target, partial: partial, locals: locals
    )
  end
end
