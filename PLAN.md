# Metis — Plan

## Mission

Metis is an open-source, self-hostable **agent platform** for individuals
and teams.

It is built on **pi**, a fast, open **agent harness** — the agentic loop,
tool execution, and extension system that turn an LLM into a working agent.
pi ships with coding tools, but its extensions, skills, and connectors make
Metis a *general-purpose personal agent*: coding is one capability, not the
boundary. The agent runs in a sandbox, so it is safe to let it run
untrusted code. The LLM provider is the user's choice — Metis is not
provider-locked.

Metis is web-first and multi-user by design. Personal productivity is the
start, not the end: the platform exists so people can **build their own
tools and share them** — across their own devices, and with their teams.

## Principles

1. **Single foundation.** One agent harness — pi. An opinionated product,
   not a generic shell over swappable backends.
2. **Multi-user by default.** Personal *and* team usage are both
   first-class. Every resource is owned by a `Team`; a personal account
   is a team of one (`docs/tenancy.md`).
3. **Sandboxed by default.** Hosted deployments run pi in an isolated
   runtime. `Local` (host shell access) is development-only.
4. **Not provider-locked.** LLM provider and model are chosen per
   conversation.
5. **Web-first.** Server-rendered Hotwire. No SPA.
6. **Capability runs in pi; Rails governs.** Skills and extensions are
   pi-native; MCP connectors arrive through a pi extension. Rails manages
   and governs them — it does not reimplement them as Rails-side tools.
7. **Made to share.** Tools and skills are built to be shared — personally
   and across a team.

## Where we are

- **Chat** — live streaming chat over `pi --mode rpc`, Turbo-broadcast and
  persisted. Working.
- **Runtimes** — `Local` (subprocess), `Docker` (container), and `E2b`
  (microVM) built; the runtime is a clean second axis (`Agent::Runtime`).
- **Extensions** — `pi --extension` wiring shipped; `web-tools` (keyless
  web search / fetch) is the first bundled extension.
- **Auth** — Devise email/password. No teams yet.

## Roadmap

Themes, roughly in dependency order:

| Theme | Goal |
|---|---|
| **Auth & tenancy** | OAuth, onboarding, then teams/orgs. Team-aware ownership from the start. |
| **Skills** | Bundled skills first, then user/team-managed skills with a UI. |
| **MCP & connectors** | One MCP-bridge extension + a team-scoped `Connector` model — the whole MCP ecosystem through a single bridge. |
| **Projects** | User-managed R&D contexts — bind a GitHub repo + a Linear project, composed into a conversation (`docs/tenancy.md`). |
| **Collaboration** | Shared conversations, shared tools, team spaces. |
| **Web UI** | A design system in the Hotwire stack — a consistent component set + design tokens. |
| **Docs** | Continuous. |

## MCP & connectors

Connecting business data to the agent — querying operational data through
a server like Metabase's MCP server — is the highest-value capability on
this roadmap. pi has **no built-in MCP** (a deliberate upstream omission),
so Metis adds it on purpose.

**Connectors are MCP, not CLIs.** pi's own guidance favors wrapping CLI
tools as skills — but a CLI assumes it is the top-level app run by an
interactive human: its auth (browser device flows, local config files)
has nowhere to land in a server-side, sandboxed, multi-user runtime, and
every CLI invents its own credential scheme. MCP has a host/client/server
model — Metis is a first-class host — and a standard OAuth 2.0 flow, so
Metis implements connector auth *once* instead of per-tool glue. Accepted
tradeoff: a service with only a CLI and no MCP server is not a connector
until an MCP server exists for it.

**One bridge, many connectors.** A single pi extension —
[`pi-mcp-adapter`](https://github.com/nicobailon/pi-mcp-adapter), the
mature MIT-licensed bridge Metis adopts — connects pi to MCP servers and
exposes their tools to the agent. Adopted once, it makes the *entire* MCP
ecosystem — Metabase, GitHub, Slack, Notion, Linear, … — available. Every
connector after the bridge is **configuration, not code**.

```
Team ─▶ Connector configs  (Metis: encrypted, team-scoped)
            │  staged per run as .mcp.json
            ▼
      pi runtime  (Docker / E2b sandbox)
        └─ pi-mcp-adapter ──▶ Metabase MCP server ──▶ Metabase
             exposes MCP tools to the agent
        └─ agent calls them like any other tool
```

Pieces:

- **`Connector` + `ConnectorCredential`** — the connector definition (which
  MCP server, its config) is owned through a `Team`; credentials are a
  separate encrypted record, either shared (a team service account) or
  per-member. See `docs/tenancy.md`.
- **`pi-mcp-adapter`** — the adopted bridge, installed as a pi package
  (`pi install`) into each pi environment at setup/build time; pi
  auto-discovers it. Reads its MCP server list from an on-disk `.mcp.json`.
- **`.mcp.json` staged per run** — the runtime writes a `.mcp.json` into
  the pi workspace from the conversation's `Connector` records, with
  credentials inlined; the file is excluded from the session archive.
- **MCP servers run inside the sandbox** — third-party MCP server code is
  contained by the Docker/E2b runtime. Principle 3 earns its keep here.
- **Marketplace** — a catalog of MCP servers a team can enable and
  configure. The catalog is metadata; the capability is the one bridge.

**pi executes, Metis governs.** pi is single-user and could never own
team-level connector governance — whose credentials, who may use them,
audit. Metis owning the `Connector` and credential layer is the right
design, and that governance layer *is* the multi-tenant product.

**Adopt vs build** is resolved — adopt `pi-mcp-adapter`, with a fork as
the fallback (full rationale and review: `docs/connectors.md`). One
concern remains: **per-turn lifecycle cost** (Open Questions) — Metis
runs pi per turn, so the bridge reconnects every MCP server on every turn.

## Week 1

Concrete deliverables:

- [x] **Docker runtime** — `Agent::Runtime::Docker`, alongside `Local` and
  `E2b`, on the same `Base` contract (`session_dir`, `extension_paths`,
  `run`). Unblocks safe multi-user hosting.
- [ ] **Bundled skills** — wire `pi --skill` the way `--extension`
  is wired (`Agent::Runtime.skill_sources` + `skill_paths`). Ship one or
  two bundled skills.
- [ ] **OAuth & onboarding** — omniauth (Google / GitHub) on Devise, and a
  first-run flow (provider + key, first conversation). Establishes real
  authenticated users.
- [x] **MCP bridge spike — resolved.** Adopt
  [`pi-mcp-adapter`](https://github.com/nicobailon/pi-mcp-adapter)
  (mature, MIT, current); Metis stages a per-run `.mcp.json`. Fork is the
  fallback if upstream's programmatic-config gap stalls. Connector
  implementation is week 2+ — see `docs/connectors.md`.
- [ ] **Docs** — keep `README.md` and `CLAUDE.md` current as the above
  lands.

Design the ownership model **team-aware now**: every resource is owned by a
`Team` and a personal account is a team of one, so shared teams slot in
later without a migration. See `docs/tenancy.md`.

## Deferred to week 2+

User/team-managed skills + UI · the MCP bridge + `Connector` model +
marketplace · the teams/orgs model · Web-UI design-system rollout.

## Open questions

1. **Team model.** The ownership boundary is settled — one `Team` unit,
   personal = team of one (`docs/tenancy.md`). Still open: how shared teams
   are created, joined, and (if hosted) billed.
2. **MCP runtime cost.** Metis runs pi per-turn in a fresh runtime; a
   naive bridge re-spawns and re-auths every MCP server each turn.
   Connection reuse, a warm runtime pool, or remote (HTTP/SSE) MCP servers
   — which mix?
3. **Sharing mechanism.** How does "build a tool and share it" work —
   export/import, a hosted registry, git-backed? Applies to skills,
   extensions, and connectors alike.
4. **Hosting model.** Self-host only, or a Metis-hosted SaaS too? This
   affects billing and how hard tenant isolation must be.
5. **Connector trust.** Secret scoping is settled — shared vs per-member
   `ConnectorCredential` (`docs/connectors.md`). Still open: who vets
   marketplace connectors.
