# Connectors

## Context

metis connects the agent to external systems — business data through
something like Metabase, plus GitHub, Slack, Notion, and the rest. pi
itself ships **no MCP support**: a deliberate upstream omission, with the
standing recommendation to wrap CLI tools as *skills* instead.

So there is a fork. metis chooses **MCP, through a bridge extension** —
not the skill + CLI path pi recommends. This doc records why.

## Decision

A connector is an MCP server. metis reaches it through
**[`pi-mcp-adapter`](https://github.com/nicobailon/pi-mcp-adapter)** — a
mature, MIT-licensed pi extension that connects pi to MCP servers and
exposes their tools to the agent. metis adopts it rather than building a
bridge of its own; forking is the fallback if its programmatic-config gap
stalls upstream. CLIs are not used as the connector mechanism.

pi-mcp-adapter is a pi *package*, installed with `pi install` into each
pi environment at setup or image-build time — `bin/setup` for local dev,
the Docker image, the E2B template. pi auto-discovers it; metis neither
vendors it nor loads it explicitly.

The adapter reads its server list from an on-disk `.mcp.json`, so metis
**stages a `.mcp.json` per run** into the pi workspace — non-secret
server definitions and inline credentials, both rendered from the
`Connector` model. That file is a per-turn projected input, excluded
from the session archive, so the secrets never become durable. A fresh
sandbox carries no other MCP config on disk, so the staged file is the
only source.

## Why not skill + CLI

A CLI is an end-to-end application built for a human at a terminal on
their own machine. That shows up in three places that matter here.

**Authentication.** A CLI authenticates the way a desktop app does — a
browser device flow, an interactive login, a token cached in `~/.config`.
metis runs pi server-side, inside a sandboxed and disposable runtime, for
many users. There is no human, no browser, and no stable home directory
for that flow to land in. To make a CLI work, metis would have to obtain
the credential out-of-band and inject it — and every CLI invents its own
scheme for being handed one (`GH_TOKEN`, `~/.aws/credentials`, a flag, a
config file). Each connector becomes bespoke credential plumbing.

**No host.** A CLI assumes it *is* the top-level program, run directly by
its operator; it has no notion of running as a component inside a larger
host. MCP is the opposite — a protocol with explicit host / client /
server roles, where metis is a first-class **host**. MCP also defines a
standard OAuth 2.0 authorization flow, so metis implements connector auth
*once*, uniformly, instead of one integration per tool.

**Structured surface.** MCP servers expose typed tool schemas and return
structured results. A CLI returns stdout meant for human eyes, which the
agent has to scrape.

## Governance

metis is multi-user. Business-data connectors need team-level governance:
whose credentials a connection uses, who may use it, an audit trail. MCP's
model — the host holds credentials and passes them per connection — maps
directly onto metis owning a `Connector` resource. A CLI has no such
concept; pi, single-user by nature, could never provide it. **pi executes;
metis governs.**

A connector is owned through metis's single tenancy unit, the `Team` — a
personal account being a team of one (see `tenancy.md`). The resource
splits in two:

- **`Connector`** — the definition: which MCP server and its non-secret
  config. Visible to every member of the owning team.
- **`ConnectorCredential`** — `belongs_to :connector`, `belongs_to :user`
  (nullable), encrypted secret.

That nullable `user_id` carries both credential shapes in one table. A row
with `user_id: nil` is a **shared** credential — a service account the
whole team uses, typical for a data source like Metabase. A row with a
`user_id` is that member's **own** credential — typical for an
identity-bearing service like GitHub or Slack, where the agent should act
as that member.

Staging `.mcp.json` for member X resolves each connector to X's own
credential if present, else the shared credential, else omits the
connector from X's `.mcp.json`. That resolution point is also the audit
anchor: which member used which connector under which credential.

## Why pi recommends CLIs — and why metis differs

pi's recommendation is sound *for pi*. pi is a single-user coding agent
run locally by a developer who already has `gh`, `aws`, and friends
installed and authenticated on their own machine. In that context a CLI
*is* the native integration, and MCP is avoidable overhead.

metis's context is the inverse: server-side, multi-user, sandboxed, no
pre-authenticated tools, no interactive operator. The same reasoning that
makes skill + CLI right for pi makes MCP right for metis. This is not a
disagreement with pi — it is the same logic applied to a different
deployment.

## What MCP does not solve

MCP standardizes the credential bridge; it does not remove it. metis is
still the OAuth broker — it runs the authorization flow, stores per-user
and per-team tokens encrypted, and hands them to the bridge. The win is
*one* uniform implementation of the right shape, not zero work.

## OAuth, incremental — sign-in and connector are different acts

Metis splits the OAuth flow into two distinct phases, on the same
underlying provider grant:

* **Sign in** asks for the minimum identity scopes only
  (`email,profile` for Google, `user:email` for GitHub). The user
  picks an account, we record a `User` + `Identity` + a per-(user,
  provider) `OauthGrant` carrying those scopes. No connectors are
  wired by sign-in.
* **Connect <connector>** sends the user *back* through OAuth via
  `connector_authorize_path_for(app)`, which builds an authorize URL
  with `scope = sign-in scopes + connector's oauth_scopes`,
  `prompt: consent`, and `include_granted_scopes: true`. The new
  grant unions with the prior one; the callback marks the connector
  as wired for this user (a `ConnectorCredential` row with no
  secret — just presence).

The win: when the deployment adds a *new* connector later (Drive on
top of Gmail), the user sees consent only for the new scope — Google
shows the new permission and asks for it explicitly. The
all-or-nothing consent at sign-in is gone, and adding scopes after
the fact actually does prompt the user.

### Where the tokens live

* **`OauthGrant`** — one per `(user, provider)`. Holds the encrypted
  access + refresh tokens, the expiry, and the union of every scope
  ever granted. Single source of truth.
* **`ConnectorCredential`** — for OAuth-shaped connectors, this is a
  *marker*: its existence says "this member has wired this connector"
  and McpConfig will stage it. The actual bearer comes from the
  user's `OauthGrant`. For token-shaped connectors, this row holds
  the secret directly (no change).

`OauthBroker.access_token_for(grant)` mints/refreshes the access
token when staging `.mcp.json`, dispatching to the per-provider
client (`OauthBroker::Clients::Github`, `::Google`) based on the
grant's `provider`. McpConfig checks that the grant covers the
connector's `oauth_scopes` before staging; if not, the connector is
dropped from the file (the member needs to Connect through the
marketplace to add the missing scopes).

### Disconnect, prune, revoke

When a member disconnects an OAuth-shaped connector from the
marketplace, the `ConnectorCredential` is destroyed and the grant's
scope set is pruned to what the member's *remaining* connectors
still need. When no OAuth-shaped connectors are left for that
provider, `OauthBroker.revoke(grant)` severs the grant on the
provider's side (Google: `https://oauth2.googleapis.com/revoke`;
GitHub: `DELETE /applications/{client_id}/grant`) and the local
`OauthGrant` is destroyed too. That's the "fully sever" semantics —
the next Connect lands as a fresh consent screen because nothing is
on file anywhere.

### Per-provider notes

* **GitHub**: metis is wired for a **GitHub App** (not a classic OAuth
  App), so the user-to-server token issued at sign-in / Connect has
  GitHub-App semantics — it preserves user identity (commits author as
  the operator), but it can only access resources where the App is
  **installed**. *Signing in alone is not enough*: a token whose App
  isn't installed on any repo returns a 404 for every private repo,
  including the user's own. The "Connect GitHub" flow therefore
  redirects to `https://github.com/apps/<slug>/installations/new`
  after the OAuth callback, prompting the user to install the App on
  the repos they want metis to act on; when they return to the
  marketplace, the connector tile shows Connected and the agent's
  per-turn `GH_TOKEN` (see *Credential pass-through to the sandbox*)
  can finally reach private content.
  - Env: `GITHUB_APP_CLIENT_ID`, `GITHUB_APP_CLIENT_SECRET`,
    `GITHUB_APP_SLUG` (the part after `apps/` in the install URL;
    without it metis skips the install redirect and the connect flow
    ends at the marketplace, leaving the user to find the install
    page themselves).
  - App settings: enable **"User-to-server token expiration"**
    (Settings → Optional features); without it GitHub issues no
    refresh token and renewals fail when the 8-hour access token
    lapses.
  - Callback URL: `/users/auth/github/callback`. Connector scopes
    requested by the catalog: `repo`, `read:user`. (For a GitHub
    App these translate into App **permissions**, not classic OAuth
    scopes — `x-oauth-scopes:` on App tokens is always empty; don't
    diagnose access issues from that header.)
* **Google**: Devise sign-in passes `access_type: offline` for a
  refresh token, `prompt: select_account` so returning users can
  pick the right account without re-consent, and
  `include_granted_scopes: true` so per-connector grants union with
  the sign-in grant. Per-connector authorize URLs override with
  `prompt: consent`. Refresh responses omit `refresh_token`;
  `OauthGrant#absorb!` preserves the prior one.

### Google connectors — self-hosted Workspace MCP

We **don't** use Google's hosted `gmailmcp.googleapis.com` because
it gates tool execution at the OAuth-client level — every call from
a non-allowlisted client (including ours) returns "caller does not
have permission" regardless of OAuth scopes. Instead each Google
catalog entry (Gmail, Google Calendar, …) points at a single
self-hosted instance of
[`chagel/google_workspace_mcp`](https://github.com/chagel/google_workspace_mcp),
run in external-OAuth mode so it validates the bearer metis sends
against Google's userinfo API per request. One server, many
connectors: the bearer's scopes decide which tools each connector
can call.

The catalog URL comes from `WORKSPACE_MCP_URL` via ERB
(`config/connector_catalog.yml`), so the same code targets a local
dev server (`http://localhost:10299/mcp/`) or a hosted instance.

`bin/dev` boots the server alongside Rails via Procfile.dev's
`workspace_mcp` entry (`bin/workspace-mcp`). The launcher defaults
to `uvx --from git+https://github.com/chagel/google_workspace_mcp
workspace-mcp` — uv pulls + caches the package on first run, no
local checkout needed. (Requires uv: https://docs.astral.sh/uv.)

Three escape hatches via env vars:

- `WORKSPACE_MCP_SOURCE` — pin a tag or commit, e.g.
  `git+https://github.com/chagel/google_workspace_mcp@v1.2.3`.
- `WORKSPACE_MCP_PROJECT` — point at a local source checkout when
  you're developing the MCP server itself.
- `WORKSPACE_MCP_PORT` — change the listen port (matches WORKSPACE_MCP_URL).

The launcher reads `GOOGLE_OAUTH_CLIENT_ID` /
`GOOGLE_OAUTH_CLIENT_SECRET` from the environment (same vars the
Devise initializer uses), exports `MCP_ENABLE_OAUTH21=true` +
`EXTERNAL_OAUTH21_PROVIDER=true`, passes
`--permissions gmail:drafts calendar:full` so both tool families
register, and auto-restarts on crash with exponential backoff.

The server picks which tools to expose based on the scopes the
bearer was granted. Each catalog entry asks Google for the scopes
its tools need: Gmail uses readonly + labels + modify + compose
(workspace-mcp's `gmail:drafts` tier); Google Calendar uses
`calendar` + `calendar.events` (the `calendar:full` tier). Expand
an entry's `oauth_scopes` to unlock more tools — e.g. add
`gmail.send` to enable the send-message tool.

## Identities, not a single provider per user

A user has many `Identity` rows — one per provider they've signed in
through or whose connector they've authorized. Sign-in looks up the
user by `(provider, uid)` first and falls back to email match, so a
GitHub user can additionally connect Google (and vice versa) without
forking a second account.

## Credential pass-through to the sandbox

Not every operator-as-agent action is an MCP call. Coding — `git clone`,
edit, commit, `gh pr create` — happens in the agent's shell, against a
working tree pi manages itself. That path needs the same identity-bearing
credential the MCP connector uses, but delivered as a process env var the
shell tools understand.

So the runtimes do exactly that: at turn start, the sandbox runtimes
(`Docker`, `E2b`) read the operator's `OauthGrant`s and project the
relevant bearers as **per-turn process env** into the agent's process —
not into a file, not into a Rails record. For GitHub: when the operator
has a grant covering the `repo` scope, the sandbox process gets
`GH_TOKEN` (consumed by `git` and `gh`) plus `GIT_AUTHOR_*` /
`GIT_COMMITTER_*` set to the operator's identity so commits carry their
handle. `Runtime::Base#sandbox_env` is the single point of composition.

The bearer reaches the container without sitting in `docker run` argv:
`--env GH_TOKEN` (no value) tells docker to forward the var from the
spawned client's environment, and `PiAgent.session(env: …)` sets it
there. `E2b` passes the same hash through `commands.run(envs: …)`. The
token has the lifetime of one `docker run` (or one E2B command), and is
gone with the container.

The threat model worth being explicit about: this credential isolation
is about **scope and lifetime, not about hiding bytes from the agent**.
The agent has to use the credential to push, so hiding it from a process
authorised to spend it would be theatre. What we actually defend is
duration (one turn) and breadth (whatever scopes the operator granted)
— and the audit trail is GitHub's own log, attributed to the operator,
not a Metis-side per-repo state plane.

`Runtime::Local` deliberately opts out: a dev's host already has their
own `gh`/`git` config, and injecting `GH_TOKEN` there would clash with
it. The sandbox runtimes are the ones with no operator at the terminal,
so they're the ones that need the projection.

## Accepted tradeoff

A service that ships only a CLI, with no MCP server, is not connectable
until an MCP server exists for it. This is an acceptable bet: MCP adoption
is fast and increasingly first-party — GitHub and Metabase both ship
official MCP servers today.

Skills are not abandoned. They remain pi's mechanism for *non-connector*
capability — a code-review skill, a commit-message helper. What is ruled
out is using CLIs as the way to reach authenticated external services.
