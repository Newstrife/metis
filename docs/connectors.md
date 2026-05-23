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

## GitHub — the OAuth shape, concretely

The GitHub connector is the first one with `auth: oauth` in the catalog,
and it sets the pattern. Each member authorizes the metis GitHub App
once; metis stores a per-member access + refresh token (encrypted, on
`ConnectorCredential`); the MCP server receives the live access token
as `Authorization: Bearer …`. The agent acts **as that member** — not
as a bot — so commits, reviews, and issue traffic carry the right
identity, and what the agent can see is exactly what the member can.

A single GitHub App registration drives this. The deployment configures
its OAuth credentials in the environment — `GITHUB_APP_CLIENT_ID` and
`GITHUB_APP_CLIENT_SECRET` (see `.env.example`). The app **must** have
"User-to-server token expiration" active under Settings → Optional
features (new Apps default to it); without it GitHub issues no refresh
token and the 8-hour access token cannot be renewed without sending the
member back through the flow.

`GithubApp::TokenService` mints/refreshes the access token on demand
when staging `.mcp.json`; if a refresh fails, the connector is dropped
silently from the rendered file, mirroring the existing "no credential
the member can use → omit" policy. Members who have not connected
simply have no GitHub entry in their `.mcp.json`.

**One flow, both jobs.** The same GitHub App OAuth handles sign-in
*and* connector authorization, through Devise OmniAuth
(`omniauth-github`). "Sign in with GitHub" on the auth pages and
"Connect" on the connectors marketplace tile both POST to
`/users/auth/github/authorize`; GitHub returns to
`/users/auth/github/callback`, where `Users::OmniauthCallbacksController`
either finds/creates the user, signs them in, and upserts the GitHub
Connector + per-member `ConnectorCredential` from the OAuth tokens — or,
if the user was already signed in, attaches the GitHub identity to them
and updates the connector. There is no separate "Connect GitHub" step:
logging in via GitHub *is* the connection.

Configure the GitHub App's callback URL as `/users/auth/github/callback`
(it can hold several; add this one if you used a different path before).

## Accepted tradeoff

A service that ships only a CLI, with no MCP server, is not connectable
until an MCP server exists for it. This is an acceptable bet: MCP adoption
is fast and increasingly first-party — GitHub and Metabase both ship
official MCP servers today.

Skills are not abandoned. They remain pi's mechanism for *non-connector*
capability — a code-review skill, a commit-message helper. What is ruled
out is using CLIs as the way to reach authenticated external services.
