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
  resumes it. No archiving.

- **`Runtime::Docker`** — the container is still `--rm` and disposable,
  but the conversation's scope is a **persistent host directory
  bind-mounted into it**. The container's ephemerality stays a security
  boundary; persistence rides on the bind mount, which is metis's
  durable storage. No archive — the host filesystem is the durable
  source. See [`coding-runtime.md`](coding-runtime.md). The constraint
  that follows (workers all need access to the persistent workspace
  root) is the same one `Local` has always had.

- **`Runtime::E2b`** — the microVM has no bind mount to a host
  filesystem; its disk is genuinely gone after the turn. Continuity
  therefore *still requires* externalizing state — archive the scope to
  Active Storage after each turn, restore it before the next. The same
  v2 shape Docker just adopted is on the roadmap (snapshot/restore via
  E2B's native `pause`/`resume`) but is not shipped yet.

`Agent::SessionArchive` is now used by `Runtime::E2b` only.

## Scope layout

    scope/
      sessions/           pi --session-dir : the transcript
      workspace/          pi cwd : files the agent itself creates
        uploads/          staged user uploads — see below

## Projected inputs are not session state

Some workspace contents are *projections* of durable Rails state, not
agent-produced output: user uploads, the rendered MCP connector config,
the agent's per-turn boot identity. Each is read straight from its
durable source at the start of every turn, and **overwritten in place**
on the persistent workspace (`Local`, `Docker`) or **excluded from the
session archive** (`E2b`) — same intent expressed in two ways.

| Projected input | Source |
|---|---|
| `workspace/uploads/*` | `Message` attachments (Active Storage) |
| `workspace/.mcp.json` | `Connector` + `ConnectorCredential` (see [`connectors.md`](connectors.md)) |
| `workspace/AGENTS.md` | `Conversation` + `Team` + runtime (see [`agent-identity.md`](agent-identity.md)) |

For `E2b`, the archive then carries only the transcript and the
agent's own working files — archive size is independent of upload,
connector, and identity-doc size, each of which costs once at its
durable source, not once per turn. For `Local` and `Docker` the
projection writes overwrite the previous turn's file in place, with
the same end state.
