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
    # The Google connectors share one self-hosted google_workspace_mcp
    # URL sourced from WORKSPACE_MCP_URL via ERB, so the deployment can
    # move between dev and prod without a code change. Verify both
    # entries pick up the same override.
    original = ENV["WORKSPACE_MCP_URL"]
    ENV["WORKSPACE_MCP_URL"] = "https://workspace-mcp.example/mcp/"
    ConnectorCatalog.instance_variable_set(:@all, nil)

    assert_equal "https://workspace-mcp.example/mcp/",
                 ConnectorCatalog.find("gmail").definition["url"]
    assert_equal "https://workspace-mcp.example/mcp/",
                 ConnectorCatalog.find("google_calendar").definition["url"]
  ensure
    original.nil? ? ENV.delete("WORKSPACE_MCP_URL") : ENV["WORKSPACE_MCP_URL"] = original
    ConnectorCatalog.instance_variable_set(:@all, nil)
  end

  test "google_calendar is an OAuth app with calendar scopes" do
    calendar = ConnectorCatalog.find("google_calendar")

    assert_equal "Google Calendar", calendar.name
    assert calendar.oauth?
    assert_equal "google", calendar.oauth_provider
    assert_includes calendar.oauth_scopes, "https://www.googleapis.com/auth/calendar"
    assert_includes calendar.oauth_scopes, "https://www.googleapis.com/auth/calendar.events"
  end
end
