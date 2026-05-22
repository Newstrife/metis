require "test_helper"

class Agent::McpConfigTest < ActiveSupport::TestCase
  def conversation
    @conversation ||= begin
      user = User.create!(email: "mcp-#{SecureRandom.hex(4)}@example.com", password: "password123")
      user.conversations.create!
    end
  end

  def add_connector(**attrs)
    conversation.user.connectors.create!({
      name: "filesystem", transport: :stdio, definition: { "command" => "npx" }
    }.merge(attrs))
  end

  def rendered
    JSON.parse(Agent::McpConfig.new(conversation).content)
  end

  test "renders an empty mcpServers map when there are no connectors" do
    assert_equal({ "mcpServers" => {} }, rendered)
  end

  test "renders a stdio connector as its definition entry" do
    add_connector(name: "fs", definition: { "command" => "npx", "args" => [ "-y", "x" ] })

    assert_equal({ "command" => "npx", "args" => [ "-y", "x" ] }, rendered["mcpServers"]["fs"])
  end

  test "merges credentials into env for a stdio connector" do
    add_connector(name: "fs",
                  definition: { "command" => "npx", "env" => { "NODE_ENV" => "production" } },
                  credential_map: { "API_KEY" => "secret" })

    assert_equal({ "NODE_ENV" => "production", "API_KEY" => "secret" },
                 rendered["mcpServers"]["fs"]["env"])
  end

  test "merges credentials into headers for an http connector" do
    conversation.user.connectors.create!(
      name: "github", transport: :http,
      definition: { "url" => "https://mcp.example/" },
      credential_map: { "Authorization" => "Bearer t" }
    )

    assert_equal({ "url" => "https://mcp.example/", "headers" => { "Authorization" => "Bearer t" } },
                 rendered["mcpServers"]["github"])
  end

  test "omits disabled connectors" do
    add_connector(name: "on")
    add_connector(name: "off", enabled: false)

    assert_equal [ "on" ], rendered["mcpServers"].keys
  end
end
