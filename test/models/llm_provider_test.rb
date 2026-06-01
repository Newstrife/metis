require "test_helper"

class LlmProviderTest < ActiveSupport::TestCase
  test "requires a unique key" do
    LlmProvider.create!(key: "openai", label: "OpenAI")
    dup = LlmProvider.new(key: "openai", label: "Other")

    assert_not dup.valid?
    assert_includes dup.errors[:key], "has already been taken"
  end

  test "ordered scope sorts by position then key" do
    a = LlmProvider.create!(key: "a", label: "A", position: 2)
    b = LlmProvider.create!(key: "b", label: "B", position: 1)

    assert_equal [ b, a ], LlmProvider.ordered
  end

  test "enabled? is true only when some model under it is enabled" do
    provider = LlmProvider.create!(key: "p", label: "P")
    assert_not provider.enabled?

    model = provider.llm_models.create!(key: "m", label: "M", enabled: false)
    assert_not provider.reload.enabled?

    model.update!(enabled: true)
    assert provider.reload.enabled?
  end

  test "set_enabled! cascades to all the provider's models" do
    provider = LlmProvider.create!(key: "p", label: "P")
    a = provider.llm_models.create!(key: "a", label: "A", enabled: true)
    b = provider.llm_models.create!(key: "b", label: "B", enabled: false)

    provider.set_enabled!(false)

    assert_not provider.reload.enabled?
    assert_not a.reload.enabled?
    assert_not b.reload.enabled?

    provider.set_enabled!(true)

    assert provider.reload.enabled?
    assert a.reload.enabled?
    assert b.reload.enabled?
  end

  test "api_key? reflects the deployment's configured keys" do
    original = Rails.application.config.x.agent.api_keys
    Rails.application.config.x.agent.api_keys = { "anthropic" => "sk-x" }

    assert LlmProvider.new(key: "anthropic").api_key?
    assert_not LlmProvider.new(key: "openai").api_key?
  ensure
    Rails.application.config.x.agent.api_keys = original
  end
end
