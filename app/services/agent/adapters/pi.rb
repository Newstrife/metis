module Agent
  module Adapters
    # Drives the pi backend via pi-agent-rb (`pi --mode rpc`) and
    # translates pi's native event stream into Agent::UiEvent objects.
    #
    # `session:` may be injected for testing; production builds one from
    # `session_options:` (passed through to PiAgent.session).
    class Pi < Base
      def initialize(conversation:, session: nil, session_options: {}, **opts)
        super(conversation: conversation, **opts)
        @injected_session = session
        @session_options = session_options
        @session = nil
      end

      def stream(input, &block)
        return enum_for(:stream, input) unless block

        active_session.prompt(input) do |pi_event|
          ui_event = translate(pi_event)
          block.call(ui_event) if ui_event
        end
      ensure
        close_session
      end

      def abort
        @session&.abort
      end

      # Translate a PiAgent::Event into an Agent::UiEvent, or nil to drop
      # events the chat UI does not render (agent_start, turn_start/end,
      # compaction, queue updates, ...).
      def translate(event)
        case event.type
        when :message_start
          ui(:message_started, event, id: message_id(event), role: message_role(event))
        when :message_update
          translate_update(event)
        when :message_end
          ui(:message_finished, event, id: message_id(event), content: message_content(event))
        when :tool_execution_start
          ui(:tool_call_started, event,
             tool_call_id: event["toolCallId"], name: event["toolName"], args: event["args"])
        when :tool_execution_update
          ui(:tool_call_progress, event,
             tool_call_id: event["toolCallId"], output: content_text(event["partialResult"]))
        when :tool_execution_end
          ui(:tool_call_finished, event,
             tool_call_id: event["toolCallId"],
             output: content_text(event["result"]),
             is_error: event["isError"] ? true : false)
        when :agent_end
          ui(:turn_finished, event)
        when :extension_error
          ui(:error, event, message: event.error_message)
        else
          event.error? ? ui(:error, event, message: event.error_message) : nil
        end
      end

      private

      def translate_update(event)
        case event.raw.dig("assistantMessageEvent", "type")
        when "text_delta"     then ui(:text_delta, event, id: message_id(event), delta: event.delta)
        when "thinking_delta" then ui(:reasoning_delta, event, id: message_id(event), delta: event.delta)
        when "error"          then ui(:error, event, message: event.error_message)
        end
      end

      def ui(type, pi_event, **data)
        Agent::UiEvent.new(type, data: data.compact, native_ref: pi_event.raw)
      end

      def active_session
        @session ||= @injected_session || PiAgent.session(**@session_options)
      end

      def close_session
        @session&.close
        @session = nil
      end

      def message_id(event)
        event.raw.dig("message", "id")
      end

      def message_role(event)
        event.raw.dig("message", "role")
      end

      def message_content(event)
        message = event.raw["message"]
        message && text_of(message["content"])
      end

      # A pi tool result / partialResult is { content: [blocks], details: }.
      def content_text(payload)
        payload && text_of(payload["content"])
      end

      def text_of(content)
        case content
        when String
          content
        when Array
          content.filter_map { |block| block["text"] if block.is_a?(Hash) && block["type"] == "text" }.join
        end
      end
    end
  end
end
