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

This is the core of the app. Metis runs on a single coding-agent
foundation — pi (see `docs/single-coding-agent-foundation.md`). The Agent
layer separates two concerns:

1. **`Agent::Adapters`** — *the agent*. `Adapters.for(conversation)` builds
   the `Pi` adapter, which drives pi and translates its native event
   stream. `#stream(input)` yields events. This layer decouples the chat
   UI from pi's wire protocol; it is not a multi-backend seam.
2. **`Agent::Runtime`** — *where* the agent runs. `Runtime::Local` runs pi
   as a local subprocess; `Runtime::E2b` runs it in an isolated microVM.
   **`Runtime::Local` is not a security boundary** — pi has shell access.

pi's native events are translated into **`Agent::UiEvent`**, a canonical
vocabulary (`text_delta`, `tool_call_started`, `turn_finished`, …) that
keeps the chat UI decoupled from pi's protocol. `UiEvent#native_ref`
keeps the raw payload for native view helpers.

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

pi's `--provider` / `--model` come from the conversation's `settings` (jsonb,
set by the new-chat composer) or fall back to `config.x.agent` deployment
defaults (`METIS_AGENT_PROVIDER` / `METIS_AGENT_MODEL`). The `--api-key` is
chosen by provider: the owner's `ApiKey` (`User#api_key_for`) if set, else the
per-provider deployment key in `config.x.agent.api_keys` (`ANTHROPIC_API_KEY` /
`OPENAI_API_KEY` / `GOOGLE_API_KEY`, read from the environment — `.env` in
development, loaded by foreman). All unset → pi uses its own config.

## Conventions

- Models use integer enums: `Conversation#backend`, `Message#role`,
  `Message#streaming_status`.
- Test parallelization is disabled below 500 tests on purpose — parallel
  workers share the filesystem and race on per-conversation scratch paths.
- Background jobs run on Solid Queue (in production); Solid Cache/Cable back
  Rails cache and Action Cable.
