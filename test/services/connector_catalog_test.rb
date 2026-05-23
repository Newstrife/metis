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

  test "ERB in the catalog yaml interpolates from the environment" do
    # The Gmail entry sources its MCP server URL from GMAIL_MCP_URL via
    # ERB, so a self-hosted google_workspace_mcp can move between dev
    # and prod without a code change. Verify the interpolation fires.
    original = ENV["GMAIL_MCP_URL"]
    ENV["GMAIL_MCP_URL"] = "https://workspace-mcp.example/mcp/"
    ConnectorCatalog.instance_variable_set(:@all, nil)

    assert_equal "https://workspace-mcp.example/mcp/",
                 ConnectorCatalog.find("gmail").definition["url"]
  ensure
    original.nil? ? ENV.delete("GMAIL_MCP_URL") : ENV["GMAIL_MCP_URL"] = original
    ConnectorCatalog.instance_variable_set(:@all, nil)
  end
end
