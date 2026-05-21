module Agent
  module Adapters
    # The pi agent (one axis of composition). Drives a PiAgent::Session
    # obtained from a Runtime and translates pi's native event stream
    # into Agent::UiEvent objects.
    #
    # The adapter knows pi — its RPC protocol, event vocabulary, and CLI
    # arguments. It knows nothing about where pi runs; that is the
    # Runtime's job. v1 binds to Runtime::Local by default.
    #
    # Continuity: when the conversation already has a pi session
    # (backend_session_id present), --continue is passed so pi reloads
    # its history. pi's session id is captured after the run for
    # Conversation#backend_session_id.
    #
    # Credentials: --provider/--model/--api-key resolve through a
    # fallback chain — per-conversation settings and the owner's stored
    # ApiKey override the deployment default in config.x.agent. All
    # unset -> pi falls back to its own configuration.
    #
    # Attachments: images are sent inline via pi's vision protocol
    # (prompt images:); other files are handed to the runtime, which
    # stages them into pi's working directory, and a note in the prompt
    # tells pi they are there.
    class Pi < Base
      def initialize(conversation:, runtime: nil, **opts)
        super(conversation: conversation, **opts)
        @runtime = runtime || Agent::Runtime.for(conversation)
        @session = nil
        @session_stats = nil
        @model_info = nil
        @last_text_message_id = nil
      end

      def stream(input, images: [], files: [], &block)
        return enum_for(:stream, input, images: images, files: files) unless block

        @last_text_message_id = nil
        @runtime.run(pi_args: pi_args, files: files) do |session|
          @session = session
          session.prompt(prompt_with_files(input, files), images: pi_images(images)) do |pi_event|
            ui_event = translate(pi_event)
            block.call(ui_event) if ui_event
          end
          @session_stats = capture_stats(session)
          @model_info = capture_model(session)
        end
      ensure
        @session = nil
      end

      # Captured after the last run (see #stream). session_stats carries
      # token/context numbers; model identity comes from get_state.
      def native_session_id = @session_stats&.dig("sessionId")
      def token_totals = @session_stats&.dig("tokens")
      def context_usage = @session_stats&.dig("contextUsage")
      def model_info = @model_info
      def runtime_info = @runtime.runtime_info

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
        [ "--mode", "rpc", "--session-dir", @runtime.session_dir.to_s,
          *resume_args, *credential_args, *extension_args ]
      end

      private

      # Image attachments become pi's inline image content.
      def pi_images(images)
        images.map { |image| PiAgent::Image.from_bytes(image.download, mime_type: image.content_type) }
      end

      # The runtime stages non-image files into pi's working directory;
      # name them in the prompt so pi knows to open them there.
      def prompt_with_files(input, files)
        names = files.map { |file| file.filename.to_s }
        return input if names.empty?

        note = "[Attached files in your working directory: #{names.join(', ')}]"
        input.present? ? "#{input}\n\n#{note}" : note
      end

      def resume_args
        conversation.backend_session_id.present? ? [ "--continue" ] : []
      end

      # Per-conversation settings (and the owner's stored ApiKey) override
      # the deployment-level defaults in config.x.agent. The api key is
      # matched to the provider. All unset -> no flags, and pi falls back
      # to its own configuration.
      def credential_args
        settings = conversation.settings || {}
        defaults = Rails.application.config.x.agent

        model = settings["model"].presence || defaults.model
        provider = settings["provider"].presence || defaults.provider

        args = []
        args += [ "--model", model ] if model.present?
        if provider.present?
          args += [ "--provider", provider ]
          key = conversation.user.api_key_for(provider).presence ||
                defaults.api_keys.to_h[provider]
          args += [ "--api-key", key ] if key.present?
        end
        args
      end

      # Load the app's bundled pi extensions (web tools, …). The runtime
      # resolves paths reachable from pi's execution environment.
      def extension_args
        @runtime.extension_paths.flat_map { |path| [ "--extension", path.to_s ] }
      end

      # pi's token usage, cost, and context-window stats for the run.
      # Never raised — stats are reporting, not the turn itself.
      def capture_stats(session)
        session.session_stats
      rescue StandardError
        nil
      end

      # The model pi resolved for the run, slimmed to id/name/provider.
      # Reporting only, so failures never raise.
      def capture_model(session)
        session.get_state.dig("data", "model")&.slice("id", "name", "provider")
      rescue StandardError
        nil
      end

      def translate_update(event)
        case event.raw.dig("assistantMessageEvent", "type")
        when "text_delta"     then ui(:text_delta, event, id: message_id(event), delta: segmented_delta(event))
        when "thinking_delta" then ui(:reasoning_delta, event, id: message_id(event), delta: event.delta)
        when "error"          then ui(:error, event, message: event.error_message)
        end
      end

      # pi splits a turn's assistant text across several messages — one per
      # run of text between tool calls — and the first delta of each new
      # message carries no leading whitespace. Concatenated naively that
      # fuses the segments ("project.The"); insert a paragraph break
      # whenever the text stream crosses into a new pi message.
      def segmented_delta(event)
        delta = event.delta.to_s
        return delta if delta.empty?

        id = message_id(event)
        delta = "\n\n#{delta}" if @last_text_message_id && id && id != @last_text_message_id
        @last_text_message_id = id if id
        delta
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
