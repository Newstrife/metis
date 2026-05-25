require "test_helper"

class Agent::IdentityTest < ActiveSupport::TestCase
  def conversation
    @conversation ||= begin
      user = User.create!(email: "id-#{SecureRandom.hex(4)}@example.com", password: "password123")
      user.conversations.create!
    end
  end

  def render(runtime_kind: "docker")
    Agent::Identity.new(conversation, runtime_kind).content
  end

  test "anchors the agent — Metis as identity, human-served" do
    out = render

    assert_match(/You are Metis/, out)
    assert_match(/human/i, out)
    assert_match(/#{conversation.user.email}/, out)
  end

  test "renders the Metis soul as behavioral guidance" do
    out = render

    assert_match(/## Soul/, out)
    assert_match(/not a chatbot behind a form/i, out)
    assert_match(/Read files, inspect context, use tools/i, out)
    assert_match(/Have judgment/i, out)
    assert_match(/external actions are\s+not/i, out)
    assert_match(/keep private\s+things private/i, out)
    assert_match(/never send\s+half-baked replies/i, out)
  end

  test "names the runtime so the agent knows its isolation posture" do
    assert_match(/`docker`.*container/i,  render(runtime_kind: "docker"))
    assert_match(/`e2b`.*microVM/i,        render(runtime_kind: "e2b"))
    assert_match(/`local`.*not a security/i, render(runtime_kind: "local"))
  end

  test "tells the agent that working-tree files persist between turns" do
    # All three runtimes are now persistent enough that this holds:
    # Local on the host filesystem, Docker via the bind mount, E2b via
    # the session archive. The agent doesn't need to know which.
    %w[local docker e2b].each do |kind|
      assert_match(/persist between turns/, render(runtime_kind: kind),
                   "runtime #{kind} should name persistence")
    end
  end

  test "lists enabled connectors with how the agent acts on them" do
    connector = conversation.team.connectors.create!(
      name: "github", transport: :http,
      definition: { "url" => "https://mcp.example/" }, catalog_key: "github"
    )
    connector.connector_credentials.create!(user: conversation.user)
    conversation.user.oauth_grants.create!(
      provider: "github", access_token: "live", refresh_token: "rt",
      expires_at: 1.hour.from_now, scopes: "user:email repo read:user"
    )

    out = render

    assert_match(/GitHub.*`github`.*OAuth/i, out)
  end

  test "explicitly notes when no connectors are wired" do
    assert_match(/None enabled/i, render)
  end

  test "an OAuth connector with no covering grant is described as not authorized, not 'as you'" do
    # Connector + credential marker exist, but the OauthGrant either
    # isn't present or doesn't cover the catalog scopes — the same
    # condition that makes McpConfig drop the connector for this turn.
    # The identity prompt must mirror that gate; if it lies, the agent
    # reads 'as you (OAuth)' and burns turns calling tools it doesn't have.
    connector = conversation.team.connectors.create!(
      name: "github", transport: :http,
      definition: { "url" => "https://mcp.example/" }, catalog_key: "github"
    )
    connector.connector_credentials.create!(user: conversation.user)
    # No OauthGrant for this user.

    out = render

    refute_match(/as you \(OAuth\)/i, out, "identity must not lie when McpConfig drops the connector")
    assert_match(/not yet authorized/i, out)
  end

  test "tells the agent that uploads and .mcp.json are projected inputs" do
    out = render

    assert_match(/uploads\//, out)
    assert_match(/\.mcp\.json/, out)
    assert_match(/projected inputs/i, out)
  end

  test "tells the agent to honor project AGENTS.md/CLAUDE.md when entering a subdirectory" do
    # pi only parent-walks context files from cwd at session start, so a
    # project at workspace/foo/AGENTS.md is never auto-loaded. The standing
    # instruction here is what makes the agent read it as a tool call so
    # the project's conventions land in the conversation.
    out = render

    assert_match(/AGENTS\.md.*CLAUDE\.md|CLAUDE\.md.*AGENTS\.md/, out)
    assert_match(/workspace\//, out)
  end

  test "renders the Coding tools section when a GitHub grant covers `repo`" do
    # The same gate Runtime::Base#sandbox_env uses to inject GH_TOKEN —
    # the identity prompt must mirror it exactly so AGENTS.md never names
    # GH_TOKEN as available when the runtime won't have injected it.
    conversation.user.oauth_grants.create!(
      provider: "github", access_token: "live", refresh_token: "rt",
      expires_at: 1.hour.from_now, scopes: "user:email repo"
    )

    out = render(runtime_kind: "docker")

    assert_match(/## Coding tools/, out)
    assert_match(/GH_TOKEN/, out)
    assert_match(/gh pr\s+create/, out)
    assert_match(/main/i, out)
    # The v2 positive framing — the working tree persists. The old
    # "push to survive" rule is gone; if it reappears here, AGENTS.md
    # and the runtime have drifted.
    assert_match(/working tree persists/i, out)
    refute_match(/scratch/i, out, "AGENTS.md must not describe the working tree as scratch")
  end

  test "renders the Coding tools section for GitHub even when grant scopes are empty (App OAuth)" do
    # GitHub Apps don't echo OAuth scopes; a connected user's grant
    # legitimately has empty scope_set. The old "covers?(repo)" gate
    # would falsely hide the section for every real GitHub user. The
    # runtime injects GH_TOKEN regardless; AGENTS.md must mirror that.
    conversation.user.oauth_grants.create!(
      provider: "github", access_token: "ghu_live", refresh_token: "rt",
      expires_at: 1.hour.from_now, scopes: nil
    )

    out = render(runtime_kind: "docker")

    assert_match(/## Coding tools/, out)
    assert_match(/GH_TOKEN/, out)
  end

  test "omits the Coding tools section when there's no GitHub grant at all" do
    # No grant → runtime can't inject GH_TOKEN. The honest gate.
    out = render(runtime_kind: "docker")

    refute_match(/## Coding tools/, out)
    refute_match(/GH_TOKEN/, out)
  end

  test "omits the Coding tools section in the Local runtime even with a covering grant" do
    # Local is dev-only — the operator's host has its own gh/git config
    # and Runtime::Local deliberately doesn't inject GH_TOKEN. AGENTS.md
    # must not promise tools the runtime isn't going to wire.
    conversation.user.oauth_grants.create!(
      provider: "github", access_token: "live", refresh_token: "rt",
      expires_at: 1.hour.from_now, scopes: "user:email repo"
    )

    out = render(runtime_kind: "local")

    refute_match(/## Coding tools/, out)
    refute_match(/GH_TOKEN/, out)
  end
end
