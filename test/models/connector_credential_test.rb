require "test_helper"

class ConnectorCredentialTest < ActiveSupport::TestCase
  def connector
    @connector ||= Connector.create!(
      team: Team.create!(name: "Acme"), name: "fs", transport: :stdio,
      definition: { "command" => "npx" }
    )
  end

  def member
    @member ||= User.create!(email: "cc-#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "a shared credential has no user" do
    assert_nil connector.connector_credentials.create!(user: nil).user
  end

  test "a per-member credential belongs to a user" do
    assert_equal member, connector.connector_credentials.create!(user: member).user
  end

  test "credentials are encrypted at rest" do
    credential = connector.connector_credentials.create!(
      user: nil, credential_map: { "TOKEN" => "super-secret-value" }
    )
    raw = ConnectorCredential.connection.select_value(
      ConnectorCredential.where(id: credential.id).select(:credentials).to_sql
    )

    assert_not_includes raw.to_s, "super-secret-value"
  end

  test "credential_map round-trips through encryption" do
    credential = connector.connector_credentials.create!(user: nil, credential_map: { "K" => "v" })

    assert_equal({ "K" => "v" }, ConnectorCredential.find(credential.id).credential_map)
  end

  test "credential_map defaults to an empty hash" do
    assert_equal({}, connector.connector_credentials.build.credential_map)
  end

  test "a connector has at most one shared credential" do
    connector.connector_credentials.create!(user: nil)

    assert_not connector.connector_credentials.build(user: nil).valid?
  end

  test "a connector has at most one credential per member" do
    connector.connector_credentials.create!(user: member)

    assert_not connector.connector_credentials.build(user: member).valid?
  end
end
