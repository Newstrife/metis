# Projects

## Context

The pain this feature solves is concrete and recurring: chatting with
the agent about *the Metis codebase* starts every conversation the
same way — a few turns of "which repo?", "the GitHub one called
metis?", "do you mean the Linear project or the GitHub project?",
"check the issue tracker — no, the Linear one, the project named
Metis." Names collide across external systems and the agent has no
canonical mapping, so every chat begins with a disambiguation
handshake before the real work can start.

A **Project** is the canonical mapping that kills that handshake.
Set up once: *"In this team, 'Metis' means `github.com/chagel/metis`,
the Linear project with id `abc-123`, and the Notion workspace
`Engineering / Metis`."* Every conversation attached to the project
inherits those pointers — the agent never has to ask which Metis.

That is the load-bearing benefit. Sidebar grouping, a freeform
about-note, and any future sharing/templating story are secondary.

## Decision: projects are an opt-in mapping registry, not a tenancy tier

Three properties define the shape of this entity:

1. **A project is a stored bundle of external-resource pointers**, one
   per connector type. Plus a name and an optional about-note.
2. **Attachment is optional, not structural.** `Conversation
   belongs_to :project, optional: true`. A team has zero projects by
   default; users opt in by creating one. Unattached conversations
   behave exactly as today.
3. **No shared execution state.** Two conversations attached to the
   same project share *only* what's projected at turn start (identity
   text + MCP config). Sandbox, pi workdir, and session transcript
   stay per-conversation. Concurrent turns within a project run in
   parallel, as they do today across conversations.

The third property is the one that warrants spelling out. An earlier
sketch had projects own a shared workspace tree and a shared paused
sandbox; that would have forced a single-writer-per-project lock,
which breaks the normal case of a user holding two conversations open
against the same project simultaneously. Once the sandbox and workdir
stay per-conversation, no lock is needed and no migration of existing
data is needed — projects layer purely additively over today's
per-conversation execution model.

Tenancy is unchanged: a project `belongs_to :team` and authorization
is still `resource.team.members.include?(user)` (see
[`tenancy.md`](tenancy.md)). Projects are an organizational
convenience inside a team, not a new permission boundary.

### Why not a tenancy tier

The "natural" shape — `Team ──< Project ──< Conversation` with
required `project_id` and an auto-created default project — was
rejected after weighing what it actually buys. Once shared sandbox
and shared workspace come off the table, a required project tier
only buys sidebar grouping and adds:

- A default-project naming problem ("Inbox"? "Personal"? unnamed?).
- Mandatory migration of every existing conversation onto the new tier.
- A cascade-delete decision (delete project → delete its chats?) that
  doesn't have an obviously correct answer.
- Cognitive overhead on every user, including those who never need
  more than a flat chat list.

Optional attachment side-steps all four. The flat chat list users see
today *is* the unattached state. Projects are something that exists
only if a user creates one.

## Data model

```ruby
class Project < ApplicationRecord
  belongs_to :team
  has_many :conversations, dependent: :nullify

  # external_refs: { "github" => { "repo" => "chagel/metis" },
  #                  "linear" => { "project_id" => "abc-123" },
  #                  "notion" => { "workspace_id" => "xyz" }, ... }
  # One key per connector type; absent key = not mapped.
end

class Conversation < ApplicationRecord
  belongs_to :project, optional: true
  # ...
end
```

- `projects(id, team_id, name, about text, external_refs jsonb,
  timestamps)`. Minimal columns — the shape may need to grow later,
  but premature columns will only confuse the surface.
- `conversations.project_id` is nullable. No backfill of existing
  conversations; they remain unattached unless the user attaches
  them.
- `dependent: :nullify` on the association: deleting a project
  detaches its conversations rather than cascading. Projects are
  decorative on top of conversations, not load-bearing under them.

`external_refs` is a jsonb map keyed by connector type because each
connector has its own ref shape: GitHub wants a repo, Linear wants a
project id, Notion wants a workspace id, Slack wants a channel id,
etc. The map is sparse — a project mapping only GitHub and Linear
just has those two keys.

## How a turn uses a project

A conversation with `project_id` present projects two pieces of the
project's state into the per-turn inputs the runtime stages (see
[`agent-identity.md`](agent-identity.md) and
[`connectors.md`](connectors.md)).

### Identity (`AGENTS.md`)

The project becomes a layer between team and conversation in the
identity projection:

    Team identity
       ↓
    Project identity   ← rendered from project.about + external_refs
       ↓
    Conversation identity

The project layer renders something like:

> *This conversation is about the **Metis** project. Codebase:
> `github.com/chagel/metis` — when the user says "the repo," that's
> it. Tickets: Linear project "Metis" (id `abc-123`). Docs: Notion
> workspace `Engineering / Metis`.*
>
> *About: <user-supplied about-note>*

The mapping prose is auto-generated from `external_refs`; the
about-note is appended verbatim. Unattached conversations skip the
project layer entirely — the identity projection is identical to
today.

### MCP config

`Agent::McpConfig` reads `project.external_refs` and renders each
enabled connector's MCP server pinned to the project's ref. The
GitHub MCP server gets `--repo chagel/metis`; the Linear MCP server
gets the target project id; etc. The agent's *tools* are
pre-targeted, not just its prose — when it reaches for "the issues,"
it's already pointing at the right tracker.

A connector with no entry in `external_refs` renders as it does today
(unscoped). Unattached conversations get today's behavior
end-to-end.

## UX

### Setting up a project

The setup flow is the value prop made visible. From the sidebar
"+ New project":

1. **Name** — freeform. ("Metis", "Q4 planning", "Mom's birthday.")
2. **For each team connector, a resource picker.** GitHub picker
   shows the user's accessible repos from the team's GitHub grant.
   Linear picker shows their accessible projects. Notion picker shows
   their workspaces. Empty selection = not mapped (that connector
   stays unscoped in this project).
3. **About** (optional) — freeform note appended to the project
   identity layer.

Pickers fetch live from the team's connector grants. The user never
types an ID. This is the only way "I never have to disambiguate
again" is actually true; otherwise the user types `chagel/metis` and
makes a typo and the agent gets even more confused than before.

### Attaching a conversation to a project

- **New chat from inside a project view** → auto-attached to that
  project. Most common path.
- **New chat from the global "+"** → unattached. The user can
  attach later if it turns out to be project-shaped.
- **Existing chat**: right-click → "Attach to project" → small
  picker. Drag from chat row to project section in sidebar also
  works.
- **Detach**: right-click → "Detach from project." The chat goes
  back to the flat list.

Attach/detach are single-column writes (`update_column :project_id,
…`). No file motion, no sandbox migration — per-conversation state
is unaffected.

### Sidebar

- **Recent chats** — unattached conversations, flat list at the top.
  This is today's chat list, unchanged.
- **Projects** — each project a foldable section below, in
  most-recent-touched order. Each section shows its conversations.

A user with zero projects sees only the flat list. No "Projects"
header, no empty-state prompt, no "you have 0 projects" moment.

### Settings drawer

Right-side drawer (Turbo Frame, not a separate page route), opened
from the project header. Three sections, in order:

1. **Name** — inline editable.
2. **External resources** — one row per team connector with the
   picker UI from setup. Editable any time; takes effect on next
   turn.
3. **About** — textarea, autosaves.

And a danger zone with **Delete project**: detaches its
conversations (they move back to the flat list), then deletes the
project row. No cascade-delete of conversations.

## What v1 is not

- **No required project** — every chat must have one. Optional
  attachment was chosen specifically to avoid this.
- **No per-project ACLs** — tenancy stays at the team (see
  [`tenancy.md`](tenancy.md)).
- **No shared sandbox / workspace** — per-conversation execution is
  preserved.
- **No concurrency lock** — conversations in the same project run in
  parallel.
- **No data migration** — existing conversations stay unattached.
- **No archive** — delete is the only terminal state. Archive is a
  half-feature; ship it when someone asks twice.
- **No tags, colors, icons, activity log, notifications** — a name
  and a config is enough.
- **No sharing** — a project is a useful unit *to* share later, but
  not in v1.
- **No project-level model override** — `Conversation#settings`
  already covers this.

## Build order

Phases stack additively; nothing is user-visible until phase 5. The
agent-side projection hardens before the chrome.

1. **Schema.** `projects` table, `conversations.project_id` nullable,
   `dependent: :nullify` on the association. No backfill. Tests for
   the tenancy invariants.
2. **Project identity layer.** `Agent::Identity` learns a middle
   project layer that renders `project.about` plus auto-prose from
   `external_refs`. No-op when `project_id` is nil. Tests assert
   layer order and absence-when-detached.
3. **MCP project scoping.** `Agent::McpConfig` reads
   `project.external_refs` and pins each connector's MCP server to
   its ref. Tests cover one mapped connector, one unmapped, and
   unattached fall-through.
4. **Resource pickers** for each connector. One small service per
   connector type that calls the team's grant to list available
   resources. GitHub: list repos. Linear: list projects. (Notion,
   Slack, etc. follow the same shape but can ship later — each
   connector ships its picker independently.)
5. **Sidebar + project view.** "+ New project" button. Project
   sections in the sidebar. Project view with a chat list and a
   header (name + settings affordance). Flat-list-of-unattached at
   the top stays unchanged.
6. **Attach / detach.** Right-click menu + drag-and-drop. Single
   `update_column` action.
7. **Settings drawer.** Name (inline), external-resources rows with
   pickers, about textarea, delete. Right-side drawer via Turbo
   Frame.

Each phase is small. The expensive moments are picker UX (phase 4 —
gets repeated per connector) and the drawer (phase 7 — has the most
small interactions). Everything else is one-PR work.

## Open questions, deferred

- **More than one external ref per connector per project.** A
  monorepo project might want both `chagel/metis` and a `chagel/
  metis-extensions` repo. The jsonb schema accommodates a list
  (`{"github": {"repos": [...]}}`); the UI doesn't, yet. Ship
  single-ref first; promote to a list when a real project needs it.
- **Auto-suggesting a project for an existing chat.** "This chat
  talks a lot about chagel/metis — attach to Metis project?"
  Suggest-never-auto-move is the right pattern, but the heuristic
  needs real usage data before it's worth designing.
- **Sharing a project.** A project is a coherent unit to share with
  a teammate (chats + mappings + about); when sharing arrives, this
  is the obvious surface. Not v1.
