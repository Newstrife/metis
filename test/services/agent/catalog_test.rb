require "test_helper"

class Agent::CatalogTest < ActiveSupport::TestCase
  test "grouped_model_options groups label/id model pairs under each provider" do
    groups = Agent::Catalog.grouped_model_options

    assert_includes groups.map(&:first), "Anthropic"
    anthropic = groups.find { |label, _| label == "Anthropic" }.last
    assert_includes anthropic, [ "Claude Opus 4.8", "claude-opus-4-8" ]
  end

  test "provider_for resolves the provider that offers a model" do
    assert_equal "openai", Agent::Catalog.provider_for("gpt-5.5")
    assert_nil Agent::Catalog.provider_for("no-such-model")
  end

  test "default_model is a model the catalog offers" do
    models = Agent::Catalog::PROVIDERS.flat_map { |provider| provider[:models].pluck(:id) }
    assert_includes models, Agent::Catalog.default_model
  end

  test "default_provider is one of the catalog providers" do
    assert_includes Agent::Catalog::PROVIDERS.map { |provider| provider[:id] },
                    Agent::Catalog.default_provider
  end
end
