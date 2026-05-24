# Coding runtime (v2)

> **Status — Docker shipped, E2b on the roadmap.** `Runtime::Docker`
> now uses the v2 shape (persistent host workspace, ephemeral
> container); `Runtime::E2b` still uses per-turn archive as described
> in [`session-persistence.md`](session-persistence.md). The shipped
> Docker shape is simpler than the persistent-named-container path
> sketched below — see "What actually shipped for Docker."

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
in place of (or alongside) `pi_session_archive`. **Not yet shipped.**

**`Runtime::Docker`** — see "What actually shipped for Docker" below.

**`Runtime::Local`** — unchanged. Persistence has always been pi-native
(the scope dir lives between turns on a stable host filesystem).
`Local` is dev-only; the new shape is for the sandbox runtimes.

### What actually shipped for Docker

The draft above proposed a long-lived `metis-c<id>` container with
`docker exec` per turn, with an eviction job to reap idle containers.
What landed is simpler: **the container stays `docker run --rm`
ephemeral, but the conversation's workspace moves from
`Workspace.scratch` (under `tmp/`) to `Workspace.persistent` (under
`storage/`) — already the shape `Local` uses — and the bind mount
into the container preserves the working tree across turns**.

The split, framed by what survives a turn:

| Survives | Doesn't |
|---|---|
| Files under the bind-mounted workspace — repo, `.git`, untracked WIP, `node_modules`, build artifacts | Anything outside the workspace — `apt install`s, global npm, `$HOME` config, `/tmp` |

For coding work the surviving column is what matters: the repo, the
in-progress branch, the installed dependencies. The "doesn't" column
is honest about what the agent should not rely on (it shouldn't `apt
install` and expect it to be there next turn).

The simpler shape avoids two pieces of infrastructure the persistent-
container shape needs:

- **No eviction job.** Containers are gone the moment the turn ends.
  Idle conversations cost no Docker resources, just disk for the
  persistent workspace.
- **No "container wedged" recovery path.** Every turn starts a fresh
  container.

It also keeps turn startup a hair slower (cost of `docker run` vs.
`docker exec`) — order of hundreds of milliseconds, not a real
problem for chat turns that take seconds to minutes. The persistent-
container shape stays available as a future optimisation if that
latency starts mattering.

### What stops being needed (for Docker)

- **`Agent::SessionArchive` for Docker conversations.** The bind mount
  carries state between turns; tar-and-Active-Storage is off the hot
  path for Docker. `SessionArchive` is retained because `E2b` still
  uses it.
- **`Workspace#reset!` in Docker's `run`.** There is no scratch dir to
  reset; the workspace is the durable state holder.
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

### Lifecycle (E2b, still future)

For the eventual E2b snapshot/restore shape, the lifecycle has more
moving parts than Docker now has:

1. **First turn** — `Sandbox.create`, stage projected inputs, run,
   `sandbox.pause()`, record the snapshot id on the `Conversation`.
2. **Subsequent turns** — `Sandbox.resume(id)`, re-stage projected
   inputs (cheap), run, `sandbox.pause()`.
3. **Idle** — after an eviction window, drop the snapshot. The next
   turn provisions fresh.
4. **Conversation deleted** — explicit teardown of any live snapshot.

Eviction is best-effort. A missing snapshot at resume time falls back
to fresh provision. Docker has none of this — its lifecycle is just
"start a container per turn"; the persistent state lives in the host
workspace dir, which `Conversation#destroy` already cleans up via
`Workspace#scope_dir`.

### Migration

Docker shipped with **no migration path**: existing conversations'
`pi_session_archive` attachments are ignored on the first v2 turn.
The user-visible loss is one-time and bounded to "the agent's prior
working tree is gone" — pi's transcript carries the conversation
history through Messages regardless. Old archive blobs can be GC'd
later out-of-band.

The future E2b cutover may want a one-time `SessionArchive.restore`
into a fresh sandbox on the first v2 turn so the existing transcript
+ working tree survive the transition. That decision belongs with
the E2b change.

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

- **E2b snapshot/restore.** When; whether the simpler bind-mount
  shape Docker landed on has any analogue (E2b has no host bind
  mount, so probably not — `pause`/`resume` is the real path).
- **Eviction window for E2b snapshots.** A starting guess of 24h
  self-host, longer hosted. Wants measurement once snapshot storage
  cost is known.
- **Docker multi-worker.** A single-host self-host is fine; a
  multi-worker deployment needs the persistent workspace root on
  shared FS (NFS or equivalent) or per-conversation host pinning.
  Same constraint `Local` has always had; worth deciding before the
  second host appears, not after.
- **Workspace size cap.** Per-conversation disk budget — a runaway
  `git clone` of a huge monorepo should fail predictably, not
  consume host disk.
