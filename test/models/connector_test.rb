require "test_helper"

class ConnectorTest < ActiveSupport::TestCase
  def owner
    @owner ||= User.create!(email: "conn-#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  # A valid stdio connector, with overrides merged in.
  def stdio_connector(**attrs)
    Connector.new({
      owner: owner, name: "filesystem", transport: :stdio,
      definition: { "command" => "npx", "args" => [ "-y", "server-filesystem" ] }
    }.merge(attrs))
  end

  test "a valid stdio connector saves" do
    assert stdio_connector.save
  end

  test "a valid http connector saves" do
    connector = Connector.new(owner: owner, name: "github", transport: :http,
                              definition: { "url" => "https://api.githubcopilot.com/mcp/" })
    assert connector.save
  end

  test "name is required" do
    assert_not stdio_connector(name: nil).valid?
  end

  test "name must be a safe identifier" do
    assert_not stdio_connector(name: "bad name!").valid?
    assert stdio_connector(name: "metabase-prod").valid?
  end

  test "name is unique per owner" do
    stdio_connector.save!
    duplicate = stdio_connector
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  test "the same name is allowed for a different owner" do
    stdio_connector.save!
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password123")
    assert Connector.new(owner: other, name: "filesystem", transport: :stdio,
                         definition: { "command" => "npx" }).valid?
  end

  test "transport is required" do
    connector = stdio_connector
    connector.transport = nil
    assert_not connector.valid?
  end

  test "a stdio connector needs a command in its definition" do
    assert_not stdio_connector(definition: { "args" => [] }).valid?
  end

  test "an http connector needs a url in its definition" do
    connector = Connector.new(owner: owner, name: "x", transport: :http, definition: {})
    assert_not connector.valid?
    assert connector.errors[:definition].any?
  end

  test "credentials are encrypted at rest" do
    connector = stdio_connector
    connector.credential_map = { "TOKEN" => "super-secret-value" }
    connector.save!

    raw = Connector.connection.select_value(Connector.where(id: connector.id).select(:credentials).to_sql)
    assert_not_includes raw.to_s, "super-secret-value"
  end

  test "credential_map round-trips through encryption" do
    connector = stdio_connector
    connector.credential_map = { "TOKEN" => "abc" }
    connector.save!

    assert_equal({ "TOKEN" => "abc" }, Connector.find(connector.id).credential_map)
  end

  test "credential_map defaults to an empty hash" do
    assert_equal({}, stdio_connector.credential_map)
  end

  test "the enabled scope returns only enabled connectors" do
    on = stdio_connector(name: "on")
    on.save!
    stdio_connector(name: "off", enabled: false).save!

    assert_equal [ on.id ], owner.connectors.enabled.pluck(:id)
  end

  test "an owner's connectors are destroyed with the owner" do
    stdio_connector.save!
    assert_difference("Connector.count", -1) { owner.destroy }
  end
end
