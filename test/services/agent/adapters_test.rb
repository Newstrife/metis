require "test_helper"

class Agent::AdaptersTest < ActiveSupport::TestCase
  test "for builds the Pi adapter for a conversation" do
    conversation = Conversation.new
    adapter = Agent::Adapters.for(conversation)

    assert_instance_of Agent::Adapters::Pi, adapter
    assert_equal conversation, adapter.conversation
  end
end
