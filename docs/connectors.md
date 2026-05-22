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
**stages a `.mcp.json` per run** into the pi workspace — connector
definitions from the `Connector` model, credentials injected as env vars
or bearer tokens. A fresh sandbox carries no other MCP config on disk, so
the staged file is the only source.

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
directly onto metis owning a `Connector` resource scoped to a user or a
team. A CLI has no such concept; pi, single-user by nature, could never
provide it. **pi executes; metis governs.**

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

## Accepted tradeoff

A service that ships only a CLI, with no MCP server, is not connectable
until an MCP server exists for it. This is an acceptable bet: MCP adoption
is fast and increasingly first-party — GitHub and Metabase both ship
official MCP servers today.

Skills are not abandoned. They remain pi's mechanism for *non-connector*
capability — a code-review skill, a commit-message helper. What is ruled
out is using CLIs as the way to reach authenticated external services.
