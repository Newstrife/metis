---
name: understanding-metis
description: Architectural knowledge of the Metis codebase (chagel/metis) — a Rails 8.1 chat UI in front of the pi agent harness. Use ONLY when working on the Metis repository.
---

# Metis Architecture

Rails 8.1 web app (Ruby 4.0.5, PostgreSQL) that puts a streaming chat
UI in front of an agent harness. v1 ships the **pi** backend, driven
via the `pi-agent-rb` gem. Hotwire (Turbo + Stimulus, importmap,
Tailwind) renders the live chat; Devise + OmniAuth handles auth.

## Read first

[`VISION.md`](../../../VISION.md) lists the project's load-bearing
guardrails — the things Metis explicitly **won't build** (no second
agent backend, no CLI-as-connector, no Rails-side MCP runtime, no
polymorphic owner, no SPA, no per-user provider keys). Honour them or
argue them on a PR.

## Two axes of composition

Everything in the agent service layer (`app/services/agent/`) sits on
two orthogonal axes:

1. **`Agent::Adapters`** — *the agent*. `Adapters.for(conversation)`
   builds the `Pi` adapter, which drives pi via `pi-agent-rb` and
   translates its native event stream. Decouples the chat UI from
   pi's wire protocol — **not** a multi-backend seam.
2. **`Agent::Runtime`** — *where* the agent runs. `Runtime::Local`
   runs pi as a host subprocess; `Runtime::Docker` runs it in a
   `--rm` container with a bind-mounted workspace; `Runtime::E2b`
   runs it in an E2B microVM that pauses + resumes by sandbox id.
   `Runtime::Local` is **not** a security boundary — pi has shell
   access to the host.

Pi's native events translate into `Agent::UiEvent` — a canonical
vocabulary (`text_delta`, `tool_call_started`, `turn_finished`, …)
that keeps the UI decoupled from pi's protocol. `UiEvent#native_ref`
preserves the raw payload for backend-aware view helpers.

## Request → response flow

```
MessagesController#create
  → creates user Message + pending assistant Message
  → enqueues ChatJob
ChatJob#perform
  → Agent::Adapters.for(conversation).stream(input) { |UiEvent| ... }
    each event → ChatBroadcaster.handle(event)  [live DOM]
    text/reasoning/tool_calls also buffered locally
  → on turn end, writes final Message (content, tool_calls, status, tokens)
  → persists session id, agent_model, runtime_info, context_usage
  → cancellation: polled every 15 events vs Conversation#cancel_requested_at
```

**Division of labor**: `ChatJob` owns *persistence* (writing the final
message content + `streaming_status`); `ChatBroadcaster` owns the *live
DOM*. Keep these separate.

## Session continuity & storage

Pi keeps a conversation's state in a scope directory
(`Agent::Workspace`): `sessions/` (its transcript), `workspace/`
(its working files), and `workspace/uploads/` (staged user uploads).
How that scope survives between turns is a **per-runtime concern** —
see [`session-persistence.md`](../../../docs/session-persistence.md):

- `Runtime::Local` keeps the scope under `storage/agent/` and relies
  on pi's own `--continue`.
- `Runtime::Docker` bind-mounts the host scope into a disposable
  `--rm` container; the host filesystem is the durable source.
- `Runtime::E2b` uses E2B's native `pause`/`resume` by sandbox id —
  first turn creates and pauses, later turns resume the same microVM.
  `EvictPausedSandboxesJob` reaps long-idle sandboxes (E2B does not
  auto-clean paused ones).

There is **no archive**. `Agent::SessionArchive` was removed; don't
reintroduce a tar-to-Active-Storage path.

### Projected inputs (re-staged each turn)

| Path | Source |
|---|---|
| `workspace/uploads/*` | `Message` attachments (Active Storage) |
| `workspace/.mcp.json` | `Connector` + `ConnectorCredential` (`Agent::McpConfig`) |
| `workspace/AGENTS.md` | `Conversation` + `Team` + runtime (`Agent::Identity`) |
| `workspace/.pi/skills/*` | The repo's `.pi/skills/` tree |

Each is read straight from its durable source at the start of every
turn and **overwritten in place** — pause/restage failures are
logged, never raised; a storage hiccup must not crash a turn the user
already saw stream.

## Tenancy

`Team`-only (`docs/tenancy.md`). Every ownable resource
(`Conversation`, `Connector`, future projects/skills) has
`belongs_to :team`. A user's personal account is a team of one,
auto-created at signup. Authorization is always
`resource.team.members.include?(user)` — no `User`-vs-`Team` branch,
no polymorphic `owner`.

## Credentials & connectors

Two distinct surfaces, separately governed:

1. **LLM provider keys** — `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
   `GOOGLE_API_KEY`. Shared, deployment-level (loaded from
   `config.x.agent.api_keys`). **No per-user provider keys.**
   `Pi#credential_args` resolves the conversation's provider/model
   (per-conversation `settings` overriding `config.x.agent` defaults)
   and matches the env-loaded key.
2. **Connector OAuth + tokens** — per-user, per-provider. One
   `OauthGrant` per `(user, provider)` holds tokens + scope union;
   `ConnectorCredential` rows are presence markers, **not** the
   token source. `Agent::McpConfig` resolves a bearer per connector
   per turn via `OauthBroker.access_token_for(grant)`.

Connectors (`Connector` + `ConnectorCredential` + `OauthGrant`) are
the user's authorization state for **MCP servers**. The agent reaches
external systems (GitHub, Google, Linear, …) through MCP, bridged into
pi by the `pi-mcp-adapter` extension — installed into each pi
environment at setup/image-build time, not loaded by Rails. See
[`connectors.md`](../../../docs/connectors.md). pi ships no MCP
support of its own; the bridge-via-extension choice (vs. pi's
recommended skill+CLI path) is documented in `VISION.md`. Don't
replace it with CLI wrappers.

The user's GitHub bearer is also injected as `GH_TOKEN` into the
sandbox environment (sandboxed runtimes only — see
`Runtime::Base#sandbox_env`), together with git author/committer
identity, so the agent's commits carry the operator's handle.

## Conventions

- Models use integer enums: `Conversation#backend`, `Message#role`,
  `Message#streaming_status`, `Connector#transport`, `Membership#role`.
- `Message#content` and `Message#reasoning` use Active Record
  encryption — credentials must be present in every environment that
  touches the model (including tests).
- Tests run serial below 500 cases — parallel workers race on
  per-conversation scratch paths in `tmp/agent/` and `storage/agent/`.
- Background jobs run on Solid Queue (production); Solid Cache/Cable
  back Rails cache and Action Cable.

## Critical dependency

`Gemfile` references `pi-agent-rb` as a **local path gem** at
`../pi-agent-rb` (sibling of this repo). It must be checked out there
or `bundle` fails. This gem drives `pi --mode rpc` and is the only
way Metis talks to pi.

## Commands

- `bin/dev` — run the app (Puma + Tailwind watch via foreman, port 3000)
- `bin/setup` — install deps, prepare the database
- `bin/rails test` — full test suite (Minitest)
- `bin/rubocop` — lint (rubocop-rails-omakase house style)
- `bin/ci` — full pipeline: rubocop, bundler-audit, importmap audit,
  brakeman, tests, seed replant

Run `bin/rubocop` and the relevant tests before committing.

## For detailed reference

- **Model details and relationships**: see [MODELS.md](MODELS.md)
- **Service layer patterns**: see [SERVICES.md](SERVICES.md)
- **Architecture docs**: `docs/` —
  [`session-persistence.md`](../../../docs/session-persistence.md),
  [`coding-runtime.md`](../../../docs/coding-runtime.md),
  [`connectors.md`](../../../docs/connectors.md),
  [`tenancy.md`](../../../docs/tenancy.md),
  [`agent-identity.md`](../../../docs/agent-identity.md)
