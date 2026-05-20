require "test_helper"

class Agent::AdaptersTest < ActiveSupport::TestCase
  test "for returns a Pi adapter for the pi backend" do
    conversation = Conversation.new(backend: :pi)
    adapter = Agent::Adapters.for(conversation)
    assert_instance_of Agent::Adapters::Pi, adapter
    assert_equal conversation, adapter.conversation
  end

  test "for raises UnsupportedBackendError for claude_code" do
    error = assert_raises(Agent::UnsupportedBackendError) do
      Agent::Adapters.for(Conversation.new(backend: :claude_code))
    end
    assert_match(/claude_code/, error.message)
  end

  test "for raises UnsupportedBackendError for codex" do
    assert_raises(Agent::UnsupportedBackendError) do
      Agent::Adapters.for(Conversation.new(backend: :codex))
    end
  end

  test "supported? reflects the v1 backend set" do
    assert Agent::Adapters.supported?("pi")
    assert Agent::Adapters.supported?(:pi)
    refute Agent::Adapters.supported?("claude_code")
    refute Agent::Adapters.supported?("codex")
  end
end
