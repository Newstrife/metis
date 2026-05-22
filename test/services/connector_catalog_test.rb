require "test_helper"

class ConnectorCatalogTest < ActiveSupport::TestCase
  test "loads apps from the catalog yaml" do
    assert ConnectorCatalog.all.any?
    assert ConnectorCatalog.all.all? { |app| app.is_a?(ConnectorCatalog::App) }
  end

  test "find returns an app by key" do
    github = ConnectorCatalog.find("github")

    assert_equal "GitHub", github.name
    assert_equal "http", github.transport
    assert_equal "https://api.githubcopilot.com/mcp/", github.definition["url"]
    assert github.oauth?
    assert_equal "github", github.oauth_provider
  end

  test "find is nil for an unknown or blank key" do
    assert_nil ConnectorCatalog.find("nope")
    assert_nil ConnectorCatalog.find(nil)
  end

  test "by_category groups the apps" do
    assert_includes ConnectorCatalog.by_category.keys, "Development"
  end
end
