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

  test "assign_oauth_token! persists access, refresh, expiry, and scope" do
    credential = connector.connector_credentials.create!(user: member)
    credential.assign_oauth_token!({
      "access_token" => "at", "refresh_token" => "rt",
      "expires_in" => 3600, "scope" => "repo"
    }, at: Time.utc(2026, 5, 22, 12))

    bundle = credential.reload.oauth_token

    assert_equal "at", bundle["access_token"]
    assert_equal "rt", bundle["refresh_token"]
    assert_equal "repo", bundle["scope"]
    assert_equal Time.utc(2026, 5, 22, 13).iso8601, bundle["expires_at"]
  end

  test "oauth_token is nil when no oauth flow has been completed" do
    assert_nil connector.connector_credentials.create!(user: nil).oauth_token
  end

  test "credential_map and oauth_token coexist in the same envelope" do
    credential = connector.connector_credentials.create!(
      user: member, credential_map: { "X-Other" => "v" }
    )
    credential.assign_oauth_token!({ "access_token" => "at" })

    assert_equal({ "X-Other" => "v" }, credential.reload.credential_map)
    assert_equal "at", credential.oauth_token["access_token"]
  end
end
