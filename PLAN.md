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
   first-class. Every resource is owned by a user or a team.
3. **Sandboxed by default.** Hosted deployments run pi in an isolated
   runtime. `Local` (host shell access) is development-only.
4. **Not provider-locked.** LLM provider and model are chosen per
   conversation.
5. **Web-first.** Server-rendered Hotwire. No SPA.
6. **Build on pi's native systems.** Skills, extensions, MCP — surface and
   manage them; do not reinvent them in Rails.
7. **Made to share.** Tools and skills are built to be shared — personally
   and across a team.

## Where we are

- **Chat** — live streaming chat over `pi --mode rpc`, Turbo-broadcast and
  persisted. Working.
- **Runtimes** — `Local` (subprocess) and `E2b` (microVM) built; the
  runtime is a clean second axis (`Agent::Runtime`).
- **Extensions** — `pi --extension` wiring shipped; `web-tools` (keyless
  web search / fetch) is the first bundled extension.
- **Auth** — Devise email/password. No teams yet.

## Roadmap

Themes, roughly in dependency order:

| Theme | Goal |
|---|---|
| **Runtimes** | Add `Docker`. A sandboxed runtime is mandatory for any shared deployment. |
| **Auth & tenancy** | OAuth, onboarding, then teams/orgs. Team-aware ownership from the start. |
| **Skills** | Project-bundled skills first, then user/team-managed skills with a UI. |
| **MCP & connectors** | Research pi's MCP support; build a connector marketplace — GitHub, Slack, Notion first. |
| **Collaboration** | Shared conversations, shared tools, team spaces. |
| **Web UI** | A design system in the Hotwire stack — a consistent component set + design tokens. |
| **Docs** | Continuous. |

## Week 1

Concrete deliverables:

- [ ] **Docker runtime** — `Agent::Runtime::Docker`, alongside `Local` and
  `E2b`, on the same `Base` contract (`session_dir`, `extension_paths`,
  `run`). Unblocks safe multi-user hosting.
- [ ] **Project-bundled skills** — wire `pi --skill` the way `--extension`
  is wired (`Agent::Runtime.skill_sources` + `skill_paths`). Ship one or
  two bundled skills.
- [ ] **OAuth & onboarding** — omniauth (Google / GitHub) on Devise, and a
  first-run flow (provider + key, first conversation). Establishes real
  authenticated users.
- [ ] **MCP research spike** — does pi consume MCP servers, and how?
  Written findings plus a connector-marketplace design sketch. No
  implementation yet.
- [ ] **Docs** — keep `README.md` and `CLAUDE.md` current as the above
  lands.

Design the ownership model **team-aware now** — a conversation or skill is
owned by a user *or* a team — even though teams themselves are week 2+, so
teams slot in without a migration.

## Deferred to week 2+

User/team-managed skills + UI · MCP connector marketplace · the teams/orgs
model · Web-UI design-system rollout.

## Open questions

1. **Team model.** How are teams created, joined, and (if hosted) billed?
   Where exactly is the personal-vs-team ownership boundary?
2. **MCP.** Does pi support MCP natively, or does that integration live in
   Metis? (The week-1 spike answers this.)
3. **Sharing mechanism.** How does "build a tool and share it" work —
   export/import, a hosted registry, git-backed? Applies to skills,
   extensions, and connectors alike.
4. **Hosting model.** Self-host only, or a Metis-hosted SaaS too? This
   affects billing and how hard tenant isolation must be.
5. **Connector trust.** Who vets marketplace connectors, and how are their
   secrets scoped per user/team?
