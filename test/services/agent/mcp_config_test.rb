require "test_helper"

class Agent::McpConfigTest < ActiveSupport::TestCase
  def conversation
    @conversation ||= begin
      user = User.create!(email: "mcp-#{SecureRandom.hex(4)}@example.com", password: "password123")
      user.conversations.create!
    end
  end

  def team = conversation.team

  def member = conversation.user

  def add_connector(**attrs)
    team.connectors.create!({
      name: "filesystem", transport: :stdio, definition: { "command" => "npx" }
    }.merge(attrs))
  end

  def rendered
    JSON.parse(Agent::McpConfig.new(conversation).content)
  end

  test "renders an empty mcpServers map when the team has no connectors" do
    assert_equal({ "mcpServers" => {} }, rendered)
  end

  test "renders a no-credential connector as its definition unchanged" do
    add_connector(name: "fs", definition: { "command" => "npx", "args" => [ "-y", "x" ] })

    assert_equal({ "command" => "npx", "args" => [ "-y", "x" ] }, rendered["mcpServers"]["fs"])
  end

  test "merges the member's own credential into a stdio connector's env" do
    connector = add_connector(name: "fs", definition: { "command" => "npx" })
    connector.connector_credentials.create!(user: member, credential_map: { "API_KEY" => "mine" })

    assert_equal({ "API_KEY" => "mine" }, rendered["mcpServers"]["fs"]["env"])
  end

  test "merges a credential into an http connector's headers" do
    connector = add_connector(name: "gh", transport: :http,
                              definition: { "url" => "https://mcp.example/" })
    connector.connector_credentials.create!(user: nil, credential_map: { "Authorization" => "Bearer t" })

    assert_equal({ "Authorization" => "Bearer t" }, rendered["mcpServers"]["gh"]["headers"])
  end

  test "falls back to the team's shared credential" do
    connector = add_connector(name: "fs", definition: { "command" => "npx" })
    connector.connector_credentials.create!(user: nil, credential_map: { "API_KEY" => "shared" })

    assert_equal({ "API_KEY" => "shared" }, rendered["mcpServers"]["fs"]["env"])
  end

  test "the member's own credential wins over the shared one" do
    connector = add_connector(name: "fs", definition: { "command" => "npx" })
    connector.connector_credentials.create!(user: nil, credential_map: { "API_KEY" => "shared" })
    connector.connector_credentials.create!(user: member, credential_map: { "API_KEY" => "mine" })

    assert_equal({ "API_KEY" => "mine" }, rendered["mcpServers"]["fs"]["env"])
  end

  test "omits a connector the member has no credential for" do
    connector = add_connector(name: "github", transport: :http,
                              definition: { "url" => "https://mcp.example/" })
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password123")
    connector.connector_credentials.create!(user: other, credential_map: { "T" => "x" })

    assert_equal [], rendered["mcpServers"].keys
  end

  test "omits disabled connectors" do
    add_connector(name: "on")
    add_connector(name: "off", enabled: false)

    assert_equal [ "on" ], rendered["mcpServers"].keys
  end
end
