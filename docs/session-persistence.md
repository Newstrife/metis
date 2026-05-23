# Session Persistence

## Context

A conversation with pi is stateful: pi keeps a session transcript (its
`--session-dir`) and a workspace (files it creates). Turn N must see turn
N−1's state. metis runs each turn as a background job on an interchangeable
worker, in a per-turn execution environment.

## Principle: persistence is a per-runtime concern

How a conversation's state survives between turns depends on *where* the
agent ran — so it belongs to the `Runtime`, not to one shared mechanism.

- **`Runtime::Local`** — pi runs as a host subprocess on a stable
  filesystem. pi's own file-based session management is enough: the scope
  lives in a persistent, conversation-stable directory and `--continue`
  resumes it. No archiving. (Valid because Local is single-operator /
  single-host by definition — multi-host production is what the sandbox
  runtimes are for.)

- **`Runtime::Docker` / `Runtime::E2b`** — the execution environment is
  isolated and disposable: a `--rm` container, a killed microVM. Its
  filesystem is, by design, separate from metis's durable storage and gone
  after the turn. Continuity therefore *requires* externalizing state —
  archive the scope to Active Storage after each turn, restore it before
  the next. This isn't optional; it is what makes a sandboxed agent
  runtime possible at all.

`Agent::SessionArchive` is the **sandbox runtimes'** persistence
mechanism — not a universal layer.

## Scope layout

    scope/
      sessions/           pi --session-dir : the transcript
      workspace/          pi cwd : files the agent itself creates
        uploads/          staged user uploads — see below

## Projected inputs are not session state

Some workspace contents are *projections* of durable Rails state, not
agent-produced output: user uploads, the rendered MCP connector config,
the agent's per-turn boot identity. Each is read straight from its
durable source at the start of every turn, and **excluded from the
session archive**.

| Projected input | Source |
|---|---|
| `workspace/uploads/*` | `Message` attachments (Active Storage) |
| `workspace/.mcp.json` | `Connector` + `ConnectorCredential` (see [`connectors.md`](connectors.md)) |
| `workspace/AGENTS.md` | `Conversation` + `Team` + runtime (see [`agent-identity.md`](agent-identity.md)) |

The archive then carries only the transcript and the agent's own
working files. Archive size becomes independent of upload, connector,
and identity-doc size — each costs once at its durable source, not
once per turn.

## Phasing

- **Phase 1 (this change)** — per-runtime persistence (Local goes
  pi-native) and uploads-as-projected-inputs.
- **Phase 2 (later)** — split the sandbox archive into `sessions/` and
  `workspace/`, and skip re-archiving `workspace/` on turns that did not
  change it.
- **Phase 3 (deferred — YAGNI)** — delta / content-addressed archiving,
  for the case where the agent itself builds a very large workspace.
