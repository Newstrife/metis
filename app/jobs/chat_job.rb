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
  rescue Agent::UnsupportedBackendError => e
    fail_message(assistant_message, broadcaster, e.message)
  rescue StandardError => e
    Rails.logger.error("ChatJob #{conversation_id} failed: #{e.class}: #{e.message}")
    fail_message(assistant_message, broadcaster, "The agent run failed.")
  end

  private

  def run(conversation, user_message, assistant_message, broadcaster)
    assistant_message.update!(streaming_status: :streaming)
    adapter = Agent::Adapters.for(conversation)
    buffer = +""
    errored = false

    adapter.stream(user_message.content) do |event|
      buffer << event[:delta].to_s if event.type == :text_delta
      errored = true if event.type == :error
      broadcaster.handle(event)
    end

    assistant_message.update!(
      content: buffer,
      streaming_status: errored ? :errored : :done
    )
    conversation.touch
  end

  def fail_message(assistant_message, broadcaster, message)
    return unless assistant_message

    assistant_message.update!(streaming_status: :errored)
    broadcaster&.fail(message)
  end
end
