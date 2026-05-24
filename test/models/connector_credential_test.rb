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

  test "oauth_grant resolves to the user's grant for the connector's provider" do
    github = github_connector
    grant = member.oauth_grants.create!(
      provider: "github", access_token: "at", scopes: "repo read:user user:email"
    )
    cred = github.connector_credentials.create!(user: member)

    assert_equal grant, cred.oauth_grant
  end

  test "oauth_grant is nil when the user has no grant for the provider" do
    github = github_connector
    cred = github.connector_credentials.create!(user: member)

    assert_nil cred.oauth_grant
  end

  test "oauth_grant is nil for a shared (user-less) credential" do
    github = github_connector
    cred = github.connector_credentials.create!(user: nil)

    assert_nil cred.oauth_grant
  end

  test "oauth_ready? for a scope-meaningful provider requires scope coverage" do
    # Gmail (Google) uses classic OAuth — scope coverage is the real
    # gate; an incomplete grant must not look connected.
    gmail = gmail_connector
    cred = gmail.connector_credentials.create!(user: member)
    grant = member.oauth_grants.create!(provider: "google", access_token: "at",
                                        scopes: "email profile")

    refute cred.oauth_ready?, "Gmail needs gmail.readonly etc.; bare sign-in scopes aren't enough"

    grant.update!(scopes: "email profile #{ConnectorCatalog.find('gmail').oauth_scopes.join(' ')}")
    assert cred.oauth_ready?
  end

  test "oauth_ready? for GitHub treats grant+token as sufficient — App OAuth carries no scopes" do
    # GitHub Apps don't echo OAuth scopes; grant.scopes is empty
    # regardless of what we asked for. Gating on coverage here would
    # show every connected GitHub user as Reconnect forever. The
    # honest gate is "did we get a token at all" — install coverage
    # is governed by the App's installation, server-side at GitHub.
    github = github_connector
    cred = github.connector_credentials.create!(user: member)

    refute cred.oauth_ready?, "no grant yet"

    member.oauth_grants.create!(provider: "github", access_token: "ghu_live", scopes: nil)
    assert cred.oauth_ready?
  end

  test "oauth_ready? for GitHub stays false when token is blank" do
    github = github_connector
    cred = github.connector_credentials.create!(user: member)
    member.oauth_grants.create!(provider: "github", access_token: nil, scopes: nil)

    refute cred.oauth_ready?, "presence of grant alone isn't enough — need a token"
  end

  private

  def github_connector
    Connector.create!(team: connector.team, name: "github", transport: :http,
                      definition: { "url" => "https://mcp.example/" },
                      catalog_key: "github")
  end

  def gmail_connector
    Connector.create!(team: connector.team, name: "gmail", transport: :http,
                      definition: { "url" => "https://mcp.example/" },
                      catalog_key: "gmail")
  end
end
