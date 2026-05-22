require "test_helper"

class ConnectorsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "cc-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in @user
  end

  def team = @user.personal_team

  test "index lists the team's connectors" do
    team.connectors.create!(name: "fs", transport: :stdio, definition: { "command" => "npx" })

    get connectors_path
    assert_response :success
    assert_select ".conn-row", 1
  end

  test "new renders the form" do
    get new_connector_path
    assert_response :success
  end

  test "create assembles a stdio connector from the structured form" do
    assert_difference("Connector.count", 1) do
      post connectors_path, params: {
        connector: { name: "fs", transport: "stdio", enabled: "1",
                     command: "npx", args: "-y\nserver-filesystem" }
      }
    end

    connector = team.connectors.last
    assert_equal "npx", connector.definition["command"]
    assert_equal [ "-y", "server-filesystem" ], connector.definition["args"]
  end

  test "create rejects an invalid connector" do
    assert_no_difference("Connector.count") do
      post connectors_path, params: { connector: { name: "", transport: "stdio" } }
    end
    assert_response :unprocessable_entity
  end

  test "update saves changes, reassembling the definition" do
    connector = team.connectors.create!(name: "fs", transport: :stdio, definition: { "command" => "npx" })

    patch connector_path(connector), params: {
      connector: { name: "fs", transport: "http", url: "https://mcp.example/" }
    }

    assert connector.reload.http?
    assert_equal "https://mcp.example/", connector.definition["url"]
  end

  test "destroy removes the connector" do
    connector = team.connectors.create!(name: "fs", transport: :stdio, definition: { "command" => "npx" })

    assert_difference("Connector.count", -1) { delete connector_path(connector) }
  end

  test "another team's connector is out of scope" do
    other = Team.create!(name: "Other")
    connector = other.connectors.create!(name: "x", transport: :stdio, definition: { "command" => "npx" })

    get edit_connector_path(connector)
    assert_response :not_found
  end
end
