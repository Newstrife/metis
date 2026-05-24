# Coding runtime (v2)

> **Status — design, not yet shipped.** This document captures the
> intended shape of the next sandbox-runtime evolution; the live
> behaviour is still per-turn ephemeral as described in
> [`session-persistence.md`](session-persistence.md).

## Context

The sandbox runtimes (`Docker`, `E2b`) are per-turn disposable today:
each turn provisions a fresh container or microvm, restores the
conversation's scope from a tar archive, runs pi, captures the scope
back, and tears the runtime down. That shape was right for the
chat-as-tool-use case metis grew out of — pi writes a small script,
runs it, returns output — and it preserves the worker-fungibility the
Rails background-job model needs.

It is the wrong shape for multi-turn coding. The cost shows up in three
places that compound on a real codebase:

- **Dependency installs** (`npm install`, `bundle install`, `cargo
  build`) pay their full cost every turn, or get committed to the repo
  to escape it. Neither answer is right.
- **WIP only survives by being pushed to GitHub** at end-of-turn. The
  agent has to choose between committing unfinished work or losing it
  — a forced distortion that no engineer working on their own laptop
  would accept.
- **Archive latency dominates the turn** as the workspace grows.
  Serializing a tarball through Active Storage on every turn is
  acceptable when "workspace" means a handful of agent-produced files;
  it stops being acceptable when it means a checked-out repo plus its
  build artifacts.

The natural unit of coding work is the *conversation*, not the turn.
The sandbox should live for the conversation.

## Decision: per-conversation sandbox lifetime via snapshot/restore

The sandbox is provisioned once at the conversation's first turn,
snapshotted at end-of-turn, and resumed at the next turn. Idle
conversations have their snapshot retained for an eviction window,
then dropped. A conversation whose snapshot has been evicted simply
provisions fresh on its next turn — same path as today's first turn.

This deliberately *is not* "long-lived sandbox pinned to a worker."
That shape would break worker fungibility: turn N would have to land
on whichever worker holds the live process. Snapshot/restore preserves
the property that any worker can pick up any turn, because the
sandbox's state lives in addressable remote storage (E2B's snapshot
store, or a shared Docker daemon's container by name) and a fresh
process binds to it at turn start.

### Per-runtime shape

**`Runtime::E2b`** — native fit. `Sandbox.create` at first turn,
`sandbox.pause()` at end-of-turn (returning the resumable id),
`Sandbox.resume(id)` at the start of the next turn. The snapshot lives
in E2B's storage, not ours. The id is persisted on the `Conversation`
in place of (or alongside) `pi_session_archive`.

**`Runtime::Docker`** — adapts with a persistent named container.
First turn: `docker run -d --name metis-c<id> …` (detached, not `--rm`).
Subsequent turns: `docker exec -i metis-c<id> pi …`. Eviction is a
periodic `docker rm -f` of containers whose conversation has been
idle past the window. The container name plays the role of the
snapshot handle.

This pattern assumes a Docker daemon reachable from every worker. A
single-host self-host deployment satisfies this trivially; a
multi-worker deployment needs either a remote Docker daemon or a
scheduler that pins jobs to the host holding the container.
Functionally the same constraint as today's `Workspace.scratch`
shared-FS requirement — moved up one layer.

**`Runtime::Local`** — unchanged. Persistence has always been pi-native
(the scope dir lives between turns on a stable host filesystem).
`Local` is dev-only; the new shape is for the sandbox runtimes.

### What stops being needed

- **`Agent::SessionArchive`** for coding conversations. The sandbox
  carries state between turns; tar-and-Active-Storage stops being on
  the hot path. (Retained for the migration window — see below.)
- **`Workspace.scratch` reset / rehydrate** in the sandbox runtimes.
  There is no per-turn scratch dir to reset.
- **The "push to survive" rule in `AGENTS.md`.** The working tree
  persists across turns; commits and pushes return to their natural
  meaning (publishing work that is ready, not a save mechanism).

### What stays the same

- **Credential pass-through.** `Runtime::Base#sandbox_env` keeps
  composing the per-turn env (`GH_TOKEN`, git identity) from the
  user's `OauthGrant`s. The bearer must remain a per-turn projection
  even though the sandbox persists — OAuth tokens refresh, and a
  stale token cached in `~/.netrc` would silently fail. Each turn
  injects a fresh bearer; the sandbox should not persist it.
- **Per-turn projected inputs** — `workspace/uploads/`,
  `workspace/.mcp.json`, `workspace/AGENTS.md` — keep being re-staged
  each turn from their durable Rails sources. The sandbox's copy is
  always a projection; the conversation's durable state lives in
  Rails. (Uploads can be incremental: only stage what's new since
  the last turn touched the sandbox.)
- **The Adapter / `UiEvent` / `ChatJob` / `ChatBroadcaster` stack.**
  Orthogonal. The runtime-shape change is below the streaming
  protocol; the chat path is unchanged.
- **The `Runtime::Base` interface.** `#run`, `#session_dir`,
  `#extension_paths`, `#mcp_config`, `#identity_content`,
  `#sandbox_env` all keep their meaning. What changes is what `#run`
  *does* under the hood.

### Lifecycle, end to end

1. **First turn** — runtime checks for a snapshot/container on the
   conversation. None exists. Provisions fresh, stages projected
   inputs, runs the turn, snapshots / leaves the container running.
   Records the snapshot id or container name on the `Conversation`.
2. **Subsequent turns** — runtime resumes from the snapshot or execs
   into the container, re-stages projected inputs (cheap; just the
   files the projection contract names), runs the turn, snapshots /
   leaves the container running.
3. **Idle** — after the eviction window (default proposed: 24h
   self-host, longer for hosted), an eviction job drops the snapshot
   / removes the container. The next turn on that conversation
   provisions fresh; the working tree is gone.
4. **Conversation deleted** — explicit teardown of any live
   snapshot / container.

Eviction is best-effort. A missing snapshot at resume time falls back
to fresh provision. The user-visible failure mode is "a long-idle
conversation lost its working tree" — recoverable by re-cloning, same
shape as today, just rarer.

### Migration

Existing conversations have a `pi_session_archive` populated by the
current model. The first v2 turn on such a conversation restores the
archive into the freshly provisioned sandbox once (the existing
`SessionArchive.restore` path), then transitions to the new shape.
The archive attachment can be removed after that turn succeeds, or
kept as a one-time backstop until eviction proves clean.

## Out of scope for this change

- **Credential model change.** OAuth user grant stays. The GitHub App
  user-to-server token path (see
  [`connectors.md`](connectors.md#credential-pass-through-to-the-sandbox))
  is a future option for narrower per-repo scoping, but does not
  block — or depend on — sandbox-lifetime work.
- **`Project` or `RepoBinding` resource.** Not introduced as part of
  this. The repo the user mentions in chat continues to be the only
  binding; the agent clones what is asked, when it is asked, using
  the bearer it was given.

## Open

- **Eviction window default.** 24h is a starting guess. Wants
  measurement once snapshot storage cost is known.
- **Snapshot storage cost on E2B.** Per-conversation, per-day. Sets
  the eviction window for hosted deployments.
- **Docker multi-worker.** A single-host self-host is fine; a
  multi-worker deployment needs a shared daemon or pinning. Worth
  deciding before the second host appears, not after.
- **Workspace size cap.** Per-conversation disk budget inside the
  sandbox — a runaway `git clone` of a huge monorepo should fail
  predictably, not consume host disk.
