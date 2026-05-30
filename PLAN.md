# Metis Plan

The evolving status and roadmap. Identity, rules, and what we won't
build live in [`VISION.md`](VISION.md); architecture in
[`docs/`](docs/).

## Where we are

- **Open source.** Public on GitHub; `pi-agent-rb` released as a gem.
- **Chat** — live streaming over `pi --mode rpc`, Turbo-broadcast and
  persisted.
- **Runtimes** — `Local` (subprocess), `Docker` (container), `E2b`
  (microVM), all on the same `Agent::Runtime::Base` contract.
  Per-conversation sandbox lifetime: Docker via persistent host
  workspace, E2b via pause/resume. See
  [`docs/coding-runtime.md`](docs/coding-runtime.md).
- **Extensions** — `pi --extension` wiring shipped; `web-tools`
  (keyless web search / fetch) is the first bundled extension.
- **Auth & tenancy** — Devise email/password, GitHub OAuth (doubles
  as connector authorization), team-of-one tenancy.
- **Connectors** — `Connector` + `ConnectorCredential` shipped;
  marketplace UI; `.mcp.json` staged per turn through
  `pi-mcp-adapter`. Catalogue today: **GitHub** and **Linear** over
  OAuth + MCP, **Gmail / Google Calendar / Google Drive** over the
  `gws` CLI + skills fallback (Google's MCP path excludes personal
  accounts — see [`docs/connectors.md`](docs/connectors.md)).
- **Skills** — pi auto-discovers them from `workspace/.pi/skills/`.
  Two sources project into one tree: the repo's `.pi/skills/` and
  team-managed `Skill` rows authored from `/settings/skills`. The
  agent can create and edit team skills mid-conversation; Metis
  ingests them at turn end. Team skills can be **imported from
  GitHub** (e.g. `anthropics/skills`) from the Marketplace tab or
  by the agent itself via `.pi/skills/.imports`. See
  [`docs/skills.md`](docs/skills.md).
- **Projects** (v1) — `Project` belongs to a team, binds external
  refs (GitHub repo, Linear project) per connector, and composes
  into a conversation. The team's project catalogue is rendered
  into per-turn `AGENTS.md` for lookup-by-mention; on-demand
  resource pickers open the bound repo/project in one click.
- **Credential pass-through** — `GH_TOKEN` and
  `GOOGLE_WORKSPACE_CLI_TOKEN` projected per turn so `git`/`gh` and
  `gws` act as the operator inside the sandbox.
- **Profile** — avatars (OAuth or upload), personalization fields,
  user-menu popup with live theme switch.

## Roadmap

Themes, roughly in dependency order:

| Theme | Goal |
|---|---|
| **More connectors** | Slack, Notion, Metabase next — each configuration on top of `pi-mcp-adapter`. GitHub and Linear shipped; Google via `gws` fallback. |
| **Dual GitHub persona** | **Shipped**: two GitHub MCP servers staged at once — `github` (`ghu_`, acts as the operator) and `github_bot` (`ghs_`, acts as `<slug>[bot]`). `GithubApp::InstallationToken` mints the bot bearer with the install id auto-resolved from the App's sole install; `McpConfig` stages `github_bot` automatically when `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` are set. The reviewing-code skill posts PR reviews via `github_bot` (GitHub forbids approving your own PR), everything else via `github`. No team/shared-credential concept. See [`docs/connectors.md`](docs/connectors.md). |
| **Projects v2** | Build on the v1 scaffold: richer external-ref types, project-scoped skills/connectors, project-level conversation defaults. |
| **Real teams** | Beyond team-of-one: invitations, memberships UI, shared connectors and conversations. |
| **Skill sharing** | Beyond GitHub import — export, registry, or git-backed publishing. Same question open #2 raises for connectors and extensions. |
| **Web UI** | A design system in the Hotwire stack — consistent component set + design tokens. |

## Next

- [ ] **Slack or Notion connector.** Continue proving "configuration,
  not code" beyond GitHub + Linear.
- [ ] **Projects in daily use.** Drive a real workflow through a
  bound repo + Linear project; let the friction shape v2.

## Open questions

1. **MCP runtime cost.** Metis runs pi per-turn in a fresh runtime; a
   naive bridge re-spawns and re-auths every MCP server each turn.
   Connection reuse, a warm runtime pool, or remote (HTTP/SSE) MCP
   servers — which mix?
2. **Sharing mechanism.** How does "build a tool and share it" work —
   export/import, a hosted registry, git-backed? Applies to skills,
   extensions, and connectors alike.
3. **Hosting model.** Self-host only, or a Metis-hosted SaaS too?
   Affects billing and how hard tenant isolation must be.
4. **Connector trust.** Who vets marketplace connectors. Secret
   scoping (shared vs per-member) is settled
   ([`docs/connectors.md`](docs/connectors.md)).
