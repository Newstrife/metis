# Metis Plan

The evolving status and roadmap. Identity, rules, and what we won't
build live in [`VISION.md`](VISION.md); architecture in
[`docs/`](docs/).

## Where we are

- **Chat** — live streaming over `pi --mode rpc`, Turbo-broadcast and
  persisted.
- **Runtimes** — `Local` (subprocess), `Docker` (container), `E2b`
  (microVM), all on the same `Agent::Runtime::Base` contract.
- **Extensions** — `pi --extension` wiring shipped; `web-tools`
  (keyless web search / fetch) is the first bundled extension.
- **Auth & tenancy** — Devise email/password, GitHub OAuth (the same
  flow doubles as connector authorization), team-of-one tenancy.
- **Connectors** — `Connector` + `ConnectorCredential` shipped;
  marketplace UI; `.mcp.json` staged per turn through
  `pi-mcp-adapter`; GitHub is the first OAuth-shaped connector.

## Roadmap

Themes, roughly in dependency order:

| Theme | Goal |
|---|---|
| **Skills** | `pi --skill` wiring + a first bundled skill, then user/team-managed skills with a UI. |
| **More connectors** | Slack, Notion, Linear, Metabase — each configuration on top of `pi-mcp-adapter`. |
| **Coding runtime (v2)** | Per-conversation sandbox lifetime via snapshot/restore — see [`docs/coding-runtime.md`](docs/coding-runtime.md). Replaces the per-turn ephemeral shape for sandbox runtimes so dependency installs, WIP, and untracked work survive across turns naturally. |
| **Projects** | User-managed R&D contexts — bind a GitHub repo + a Linear project, composed into a conversation ([`docs/tenancy.md`](docs/tenancy.md)). |
| **Real teams** | Beyond team-of-one: invitations, memberships UI, shared connectors and conversations. |
| **Web UI** | A design system in the Hotwire stack — consistent component set + design tokens. |

## Next

- [ ] **Bundled skills.** Wire `pi --skill` the way `--extension` is
  wired (`Agent::Runtime.skill_sources` + `skill_paths`); ship one or
  two bundled skills.
- [ ] **A second connector.** Pick the most useful — likely Linear or
  Metabase — and prove the "configuration, not code" claim.
- [ ] **Project resource.** First scaffolding from
  [`docs/tenancy.md`](docs/tenancy.md).

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
