require "test_helper"

class Agent::CatalogTest < ActiveSupport::TestCase
  test "provider_options pairs each provider's label with its id" do
    assert_includes Agent::Catalog.provider_options, [ "Anthropic", "anthropic" ]
  end

  test "models_by_provider lists value/label models for every provider" do
    catalog = Agent::Catalog.models_by_provider
    expected = Agent::Catalog::PROVIDERS.map { |provider| provider[:id] }

    assert_equal expected.sort, catalog.keys.sort
    catalog.each_value do |models|
      assert models.any?
      assert(models.all? { |model| model["value"].present? && model["label"].present? })
    end
  end

  test "default_provider is one of the catalog providers" do
    assert_includes Agent::Catalog::PROVIDERS.map { |provider| provider[:id] },
                    Agent::Catalog.default_provider
  end
end
