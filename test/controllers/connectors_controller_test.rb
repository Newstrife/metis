require "test_helper"

class ConnectorsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "cc-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in @user
  end

  def team = @user.personal_team

  def github_connector
    team.connectors.create!(catalog_key: "github", name: "github",
                            transport: :http, definition: { "url" => "https://mcp.example/" })
  end

  test "the gallery lists catalog apps" do
    get connectors_path
    assert_response :success
    assert_select ".app-tile"
  end

  test "new with an oauth app renders the authorize button" do
    get new_connector_path(app: "github")

    assert_response :success
    assert_select "a[href=?]", connector_github_start_path
  end

  test "new with an already-connected app redirects to manage" do
    connector = github_connector
    get new_connector_path(app: "github")
    assert_redirected_to edit_connector_path(connector)
  end

  test "new without an app renders the custom form" do
    get new_connector_path
    assert_response :success
  end

  test "POSTing to connect an oauth app redirects through its OAuth start" do
    assert_no_difference([ "Connector.count", "ConnectorCredential.count" ]) do
      post connectors_path, params: { catalog_key: "github", credential: "ghp_secret" }
    end

    assert_redirected_to connector_github_start_path
  end

  test "creating a custom connector from the structured form" do
    assert_difference("Connector.count", 1) do
      post connectors_path, params: {
        connector: { name: "fs", transport: "stdio", command: "npx", args: "-y" }
      }
    end
    assert_equal "npx", team.connectors.last.definition["command"]
  end

  test "the manage page renders for a connected app" do
    get edit_connector_path(github_connector)
    assert_response :success
  end

  test "updating an oauth app ignores any typed-in credential" do
    connector = github_connector
    patch connector_path(connector), params: { credential: "ghp_new" }

    assert_nil connector.credential_for(@user)
  end

  test "disconnect removes the connector" do
    connector = github_connector
    assert_difference("Connector.count", -1) { delete connector_path(connector) }
  end

  test "another team's connector is out of scope" do
    other = Team.create!(name: "Other")
    connector = other.connectors.create!(name: "x", transport: :stdio, definition: { "command" => "npx" })

    get edit_connector_path(connector)
    assert_response :not_found
  end
end
