# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Metis is a Rails 8.1 web app (Ruby 4.0.5, PostgreSQL) that puts a chat UI in
front of coding agents. v1 ships the **pi** backend, driven via the
`pi-agent-rb` gem. Hotwire (Turbo + Stimulus, importmap, Tailwind) renders the
live streaming chat; Devise handles auth.

## Commands

- `bin/dev` — run the app (Puma + Tailwind watch via foreman, port 3000)
- `bin/setup` — install deps, prepare the database
- `bin/rails test` — full test suite (Minitest)
- `bin/rails test test/services/agent/adapters/pi_test.rb:42` — single test by file:line
- `bin/rubocop` — lint (rubocop-rails-omakase house style)
- `bin/ci` — full CI pipeline: rubocop, bundler-audit, importmap audit, brakeman, tests, seed replant
- `bin/brakeman` / `bin/bundler-audit` — security scans

Run `bin/rubocop` and the relevant tests before committing.

## Critical dependency

`Gemfile` references `pi-agent-rb` as a **local path gem** at `../pi-agent-rb`
(sibling of this repo). It must be checked out there or `bundle` fails. This
gem drives `pi --mode rpc` and is the only way the app talks to the pi agent.

Active Record encryption is used for `Message#content` and `ApiKey#key`, so
encryption keys must be present in Rails credentials for any environment that
touches those models (including tests).

## Architecture

### The Agent service layer (`app/services/agent/`)

This is the core of the app. It composes a coding agent along **two axes**:

1. **`Agent::Adapters`** — *which* agent runs. `Adapters.for(conversation)`
   dispatches on `conversation.backend`. v1 implements only `Pi`;
   `claude_code` and `codex` are in the enum but raise
   `UnsupportedBackendError`. An adapter's `#stream(input)` yields events.
2. **`Agent::Runtime`** — *where* the agent runs. `Runtime::Local` runs pi as
   a local subprocess; `Runtime::E2B` (microVM isolation) is planned.
   **`Runtime::Local` is not a security boundary** — pi has shell access.

Every backend translates its native event stream into **`Agent::UiEvent`**, a
canonical vocabulary (`text_delta`, `tool_call_started`, `turn_finished`, …)
so the chat UI is backend-agnostic. `UiEvent#native_ref` keeps the raw payload
for backend-aware view helpers.

### Request → response flow

1. `MessagesController#create` creates a `user` message and a `pending`
   `assistant` message, then enqueues `ChatJob`.
2. `ChatJob#perform` runs one turn: it gets the adapter, calls `#stream`, and
   for each `UiEvent` hands it to `ChatBroadcaster` while buffering text.
3. `ChatBroadcaster` maps each `UiEvent` to a Turbo Stream broadcast on the
   conversation's stream.

**Division of labor:** `ChatJob` owns *persistence* (writing the final message
content + `streaming_status`); `ChatBroadcaster` owns the *live DOM*. Keep
these separate.

### Session continuity & storage

pi keeps its conversation memory in a session directory. The local copy is
**disposable scratch** under `tmp/agent/u<user>/c<conversation>/`
(`Agent::Workspace` — the single place path layout is decided). The **durable,
worker-independent copy** is a gzipped tar held as the conversation's Active
Storage attachment (`Agent::SessionArchive`): restored before a run, captured
after. Combined with `Conversation#backend_session_id` + pi's `--continue`
flag, any job worker can resume any conversation.

Archive persistence failures are logged, never raised — a storage failure must
not crash a turn the user already saw stream.

### Credentials

pi's `--provider` / `--model` / `--api-key` resolve through a fallback chain:
per-conversation `Conversation#settings` (jsonb) and the owner's `ApiKey`
(`User#api_key_for`) override a deployment-level default in `config.x.agent`
(`METIS_AGENT_PROVIDER` / `METIS_AGENT_MODEL` / `METIS_AGENT_API_KEY`; the key
is also read from Rails credentials at `agent.api_key`). All unset → pi uses
its own config. There is no per-user settings UI yet — the deployment default
is the working path; `settings` / `ApiKey` are override seams.

## Conventions

- Models use integer enums: `Conversation#backend`, `Message#role`,
  `Message#streaming_status`.
- Test parallelization is disabled below 500 tests on purpose — parallel
  workers share the filesystem and race on per-conversation scratch paths.
- Background jobs run on Solid Queue (in production); Solid Cache/Cable back
  Rails cache and Action Cable.
