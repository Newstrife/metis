# Metis Service Layer

Most of the interesting code lives under `app/services/agent/` and
`app/services/oauth_broker/`. The rest is a thin Rails app.

## `Agent::Adapters` — *the agent*

```ruby
# app/services/agent/adapters.rb
Agent::Adapters.for(conversation, **opts)  # → Pi.new(conversation:, **opts)
```

This is **not** a multi-backend seam — pi is the only adapter.
`Adapters` exists to decouple `ChatJob`/`ChatBroadcaster` from pi's
wire protocol, so view code never imports `PiAgent::*`.

### `Agent::Adapters::Pi`

Drives one `PiAgent::Session` (obtained from a `Runtime`) and
translates pi's native event stream into `Agent::UiEvent`s.

```ruby
def stream(input, images: [], files: [], &block)
  @runtime.run(pi_args: pi_args) do |session|
    @session = session
    session.prompt(prompt_with_files(input, files), images: pi_images(images)) do |pi_event|
      ui_event = translate(pi_event)
      block.call(ui_event) if ui_event
    end
    @session_stats = capture_stats(session)   # tokens, contextUsage, sessionId
    @model_info    = capture_model(session)   # {id, name, provider}
  end
ensure
  @session = nil
end
```

`#translate` collapses pi's event vocabulary onto `Agent::UiEvent`'s
nine types and drops events the UI doesn't render (agent_start,
turn_start/end, compaction, queue updates). Tool events
(`tool_execution_start/update/end`) map to
`tool_call_started/progress/finished`; assistant `message_update` is
split by `assistantMessageEvent.type` into `text_delta` /
`reasoning_delta` / `error`. `#segmented_delta` inserts `\n\n` when
pi crosses into a new assistant message between tool calls — pi
strips leading whitespace per message and naive concatenation
fuses segments ("project.The").

`#pi_args` composes:
- `--mode rpc --session-dir <runtime.session_dir>`
- `--continue` when `conversation.backend_session_id.present?`
- `#credential_args` — `--model`, `--provider`, `--api-key`
  (per-conversation `settings` overrides `config.x.agent` defaults;
  the api key is the env-loaded deployment key matched to provider)
- `#extension_args` — `--extension <path>` per
  `Agent::Runtime.extension_sources`

### `Agent::UiEvent`

Frozen canonical event with nine types:

```
message_started message_finished
text_delta reasoning_delta
tool_call_started tool_call_progress tool_call_finished
turn_finished error
```

`#native_ref` preserves the raw pi payload; backend-aware view
helpers can reach in, but default rendering ignores it.
`TERMINAL_TYPES = [:turn_finished]`.

## `Agent::Runtime` — *where the agent runs*

```ruby
Agent::Runtime.for(conversation)  # picks per config.x.agent.runtime
Agent::Runtime.extension_sources  # Dir.glob(.pi/extensions/*/index.ts).sort
```

### `Runtime::Base` contract

```ruby
def session_dir       # path for pi --session-dir
def extension_paths   # pi extensions reachable from this runtime
def run(pi_args:) { |session| ... }  # provision → yield → finalize
def runtime_info      # { "runtime" => kind, … }
def sandbox_env       # per-turn env: GH_TOKEN + git author/committer (sandboxed only)
```

`Base#mcp_config` renders `Agent::McpConfig.new(conversation).content`;
`Base#identity_content` renders `Agent::Identity.new(conversation, kind).content`.
Subclasses pull those at run time and stage them.

### `Runtime::Local`

Pi as a host subprocess — single-operator / dev runtime. Scope under
`storage/agent/u<id>/c<id>/`. Pi's own file-based session management
carries continuity; `--continue` resumes. **Not a security boundary.**

```ruby
def run(pi_args:)
  workspace.ensure!
  workspace.stage_uploads(conversation.uploaded_files)
  workspace.stage_mcp_config(mcp_config)
  workspace.stage_identity(identity_content)
  workspace.stage_skills
  session = PiAgent.session(args: pi_args, cwd: workspace.workspace_dir.to_s)
  yield session
ensure
  session.close
end
```

### `Runtime::Docker`

Same scope on host, bind-mounted into a `--rm` container. Container
ephemerality is the security boundary; persistence rides the bind
mount. Calls the same `Workspace#stage_*` methods, then runs `docker
run …` with the workspace dir mounted and the extensions dir
read-only-mounted.

### `Runtime::E2b`

Pi inside an E2B microVM. The microVM lives across turns — first
turn creates and pauses, later turns connect+resume. Scope persists
*by being the same VM*. Eviction is metis's responsibility
(`EvictPausedSandboxesJob`); E2B keeps paused sandboxes indefinitely.

No bind mount — `stage_*` methods are reimplemented on the runtime
using `sandbox.files.write(remote_path, bytes)`. Extension files are
uploaded each turn so an extensions update reaches in-flight
conversations.

```ruby
SCOPE_DIR      = "/home/user/metis"
WORKSPACE_DIR  = "#{SCOPE_DIR}/workspace"
EXTENSIONS_DIR = "/home/user/pi-extensions"  # outside SCOPE_DIR — restaged each turn

def run(pi_args:, &block)
  sandbox = acquire_sandbox    # resume_existing or create_fresh
  @sandbox_id = sandbox.sandbox_id
  execute(sandbox, pi_args: pi_args, &block)
ensure
  pause_sandbox(sandbox) if sandbox
end

# pause_sandbox: best-effort. A failure logs, force-kills the VM,
# clears e2b_sandbox_id — next turn provisions fresh. Must NEVER raise:
# the turn the user already saw stream cannot crash on end-of-run.
```

`self.kill_sandbox(id)` swallows `E2B::NotFoundError` — used by
`Conversation#before_destroy` and `EvictPausedSandboxesJob`, both of
which hold a stored id but no live `Sandbox` handle.

## `Agent::Workspace`

A thin wrapper around the host filesystem scope:

```
scope/
  sessions/                pi --session-dir : transcript
  workspace/               pi cwd : files the agent creates
    uploads/               staged user uploads
    .mcp.json              MCP connector config (per turn)
    AGENTS.md              boot identity (per turn)
    .pi/skills/            project skills tree (per turn)
```

Two roots — `SCRATCH_ROOT = tmp/agent`, `PERSISTENT_ROOT = storage/agent` —
because persistence is a per-runtime concern. `Local` uses
`Workspace.persistent`; archive-shaped runtimes (none today) would
use `Workspace.scratch`.

`stage_uploads` basenames the filename so a crafted name can't
escape; `stage_skills` clears `workspace/.pi/skills/` first so a
deleted source skill disappears.

## `Agent::McpConfig`

Renders the `.mcp.json` `pi-mcp-adapter` reads, from the
conversation team's `Connector`s. Each connector resolves to the
member's credential (own → team-shared → drop). An OAuth-shaped
connector whose grant is missing, missing required scopes, or fails
to refresh is dropped — `Identity#connectors_block` mirrors this gate
exactly so the AGENTS.md never advertises a connector McpConfig
silently omitted (the agent would burn turns trying tools it doesn't
have).

```ruby
def to_h
  {
    "mcpServers" => connectors.filter_map { |c| [c.name, server_entry(c)] if server_entry(c) }.to_h
  }
end

# secrets_for:
#   nil               → drop the connector
#   {}                → keep (no-auth server)
#   {header => value} → merge into entry[stdio ? "env" : "headers"]
```

## `Agent::Identity`

Renders `AGENTS.md` — the boot file pi auto-loads from cwd each turn.
Shapes the agent's sense of place (operator, team, runtime,
connectors, uploads, soul).

Scope is **environment context** only — never Metis's product
guardrails (VISION.md). Telling pi "no SPA" would leak Metis-the-
product's contributor constraints into the user's work.

`coding_tools_block` only renders when `sandbox_env` actually injects
`GH_TOKEN` this turn — gate mirrors `Runtime::Base#sandbox_env`
exactly (sandboxed runtime + valid github grant + `repo` scope).
Naming `GH_TOKEN` when nothing is in env burns turns on tools the
agent doesn't have.

## `Agent::Catalog`

Provider/model options for the new-chat composer. Hand-maintained
list — edit `PROVIDERS` to match what the deployment's pi backend
supports. Drives only the composer's dropdowns; chosen values land
in `Conversation#settings` and pass through verbatim as pi's
`--provider`/`--model`.

```ruby
Catalog.provider_for(model_id)     # find which provider offers a model
Catalog.default_model              # composer pre-selection
Catalog.grouped_model_options      # for grouped_options_for_select
```

## `ChatJob` & `ChatBroadcaster`

`ChatJob` runs **one** turn:
1. `assistant_message.update!(streaming_status: :streaming)`
2. `adapter.stream(input) { |event| broadcaster.handle(event); buffer_text/reasoning/tools(event) }`
3. Every 15 events, poll `Conversation#cancel_requested_at` against
   `message.started_at` — stale stamps from prior turns don't count.
   On match: `adapter.abort`, mark canceled.
4. Persist final message (`content`, `reasoning`, `tool_calls`,
   `streaming_status`, `finished_at`, token deltas) + persist
   session id, agent_model, runtime_info, context_usage on conversation.
5. `broadcaster.refresh_usage / collapse_activity / refresh_composer`.

Failure path: `fail_message` *reloads* the message first to drop dirty
in-memory attributes from a failed persist — otherwise the recovery
update flushes the same poisoned payload (e.g. a `tool_calls` bag with
a U+0000 byte) and rolls back too.

`ChatBroadcaster` maps each `UiEvent` to a Turbo Stream:
- `text_delta` → `broadcast_update` with the whole body re-rendered as
  Markdown (innerHTML replace, not append — keeps open code fences /
  half-built tables rendering correctly as more text arrives).
- `reasoning_delta` → append to the reasoning disclosure.
- `tool_call_started` → append a tool card, collapse the previous.
- `tool_call_progress/finished` → replace the card; only the latest
  stays open.
- `turn_finished` → remove the typing indicator.
- `error` → append into the message card (not the body — body's
  innerHTML is replaced on every text delta and would swallow it).

`#record_tool` accumulates `name`/`args`/`output`/`is_error` keyed by
`tool_call_id` — progress/finished events carry no name/args, so
replacing the card naively would blank them.

## `OauthBroker` + `OauthBroker::Clients::{Github,Google,Linear}`

Provider-agnostic token broker. `access_token_for(grant)` returns the
current bearer, refreshing through the provider's token endpoint when
stale (within `REFRESH_LEEWAY`) or when stored token is blank (legacy
backfill row). `bearer_for(user:, provider:, required_scopes:)` is
the entry point for `Runtime::Base#sandbox_env`.

Also the **single source of truth for the strategy/provider name
split**: Identity stores the omniauth strategy name
(`google_oauth2`), OauthGrant + catalog use the canonical name
(`google`). All translation goes through `normalize_provider` /
`omniauth_strategy`.

`scope_check_meaningful?(provider)` returns false for `github` —
GitHub Apps' OAuth response carries no scopes (App permissions on
the App's settings page are the real gate), so `grant.scopes` ends
up empty/incomplete regardless. Callers fall back to "grant + token
present" instead of `covers?(...)`.

`revoke(grant)` revokes server-side and is best-effort — a network
failure logs and returns rather than blocking; the local destroy
still happens.

## `OmniauthConnector`

Translates an OmniAuth callback into Metis's durable state. Called
in sequence by the OmniAuth callback:

1. **Always**: `record_grant(user, auth, provider:)` — find-or-init
   the `OauthGrant`, absorb the token bundle. Sign-in goes through
   this and only this; the grant ends up holding just the sign-in
   scopes (per `OauthBroker::SIGN_IN_SCOPES`).
2. **When the authorize URL carried `connect=<key>`**:
   `activate_connector(user, app, auth)` — find-or-init the
   `Connector` and the per-member `ConnectorCredential` marker. The
   token already lives in the grant from step 1; this row is just
   the presence signal `McpConfig` keys off.

## `ConnectorCatalog`

Curated MCP-server "apps", loaded from `config/connector_catalog.yml`
(ERB processed before YAML so entries can interpolate env vars).
Each app is a template — connecting one resolves it into a team's
`Connector`. `App#resolved_definition(inputs)` fills `%{key}`
placeholders from user input; `App#credential_map_for(secret)` shapes
the user's secret into the header map a `ConnectorCredential` holds.

## Provider apps (`github_app/`, `google_app/`, `linear_app/`)

Tiny per-provider config holders:
- `*App::Config` — client_id, client_secret, redirect URI, allowed
  scopes, callback URL.
- `GithubApp::OauthClient` — GitHub-specific OAuth token exchange and
  refresh (the others use stock OAuth2).

These exist because the three providers diverge in non-trivial ways
(GitHub App vs. OAuth App, Google's offline-access dance, Linear's
connector-only model). Keep per-provider quirks here rather than
leaking into `OauthBroker` core.

## `EvictPausedSandboxesJob`

Recurring job (wired in `config/recurring.yml`). Finds conversations
with an `e2b_sandbox_id` and `updated_at < cutoff`
(`config.x.agent.e2b_eviction_window`), kills the sandbox, clears
the id. Best-effort per row — a per-conversation failure logs and
the loop continues; one bad row mustn't stall the whole eviction.

The next turn against an evicted conversation provisions fresh — the
working tree is gone, the message history is not.

## What's deliberately absent

Per `VISION.md`:
- No second agent backend (pi is *the* backend).
- No Rails-side MCP runtime — MCP servers are bridged into pi via
  `pi-mcp-adapter` extension, **not** loaded by Rails.
- No polymorphic `owner` — tenancy is `Team`-only.
- No SPA — Hotwire all the way down.
- No per-user provider keys — LLM keys are deployment-shared.
- No `Agent::SessionArchive` — runtimes own persistence; no
  tar-to-Active-Storage path.

If a temptation here pulls you toward one of those, push back or
argue it on a PR.
