require "fileutils"

module Agent
  module Adapters
    # Drives the pi backend via pi-agent-rb (`pi --mode rpc`) and
    # translates pi's native event stream into Agent::UiEvent objects.
    #
    # Continuity: each conversation gets a dedicated pi session directory.
    # The first run creates a session; later runs pass --continue so pi
    # reloads its own history. pi's session id is captured after each run
    # and persisted on Conversation#backend_session_id.
    #
    # Credentials: --provider/--model come from conversation.settings;
    # --api-key from the owner's stored ApiKey for that provider. When
    # unset, pi falls back to its own configuration.
    #
    # `session:` may be injected for testing.
    class Pi < Base
      SESSION_ROOT = Rails.root.join("tmp/pi_sessions")

      def initialize(conversation:, session: nil, **opts)
        super(conversation: conversation, **opts)
        @injected_session = session
        @session = nil
        @native_session_id = nil
      end

      attr_reader :native_session_id

      def stream(input, &block)
        return enum_for(:stream, input) unless block

        session = active_session
        session.prompt(input) do |pi_event|
          ui_event = translate(pi_event)
          block.call(ui_event) if ui_event
        end
        @native_session_id = capture_session_id(session)
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

      # pi CLI arguments for this conversation's run.
      def pi_args
        [ "--mode", "rpc", "--session-dir", session_dir.to_s, *resume_args, *credential_args ]
      end

      private

      def resume_args
        conversation.backend_session_id.present? ? [ "--continue" ] : []
      end

      def credential_args
        settings = conversation.settings || {}
        args = []
        args += [ "--model", settings["model"] ] if settings["model"].present?

        provider = settings["provider"]
        if provider.present?
          args += [ "--provider", provider ]
          key = conversation.user.api_key_for(provider)
          args += [ "--api-key", key ] if key.present?
        end
        args
      end

      def session_dir
        SESSION_ROOT.join(conversation.id.to_s)
      end

      def active_session
        @session ||= @injected_session || begin
          FileUtils.mkdir_p(session_dir)
          PiAgent.session(args: pi_args)
        end
      end

      def capture_session_id(session)
        session.session_stats["sessionId"]
      rescue StandardError
        nil
      end

      def close_session
        @session&.close
        @session = nil
      end

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
