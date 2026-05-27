# Skills

## Context

Skills are pi's native unit of recallable know-how: a directory with a
`SKILL.md` (frontmatter `name` + `description`, markdown body) and any
supporting files. pi auto-discovers them at runtime — when the model
sees a task that matches a skill's description, it loads the body as
ambient instructions for that turn.

Today Metis ships **system skills** only: the repo's `.pi/skills/` tree
is copied into `workspace/.pi/skills/` once per turn by
`Agent::Workspace#stage_skills`. They are versioned in git, identical
for every team, edited by committing to the repo.

This doc covers the next layer: **team-managed skills**, authored in
the Metis UI (or by the agent itself, via filesystem write), persisted
in the database, projected into `workspace/.pi/skills/<slug>/` alongside
the repo tree so pi auto-discovers them the same way it discovers
system skills. The goal stated in [`VISION.md`](../VISION.md) — *"a
platform where people build their own tools and share them"* — starts
here.

Out of scope for v1: agent-authored skills, cross-team sharing,
checkout/locking, versioning. See *Path to agent authoring* and *Open
questions* at the bottom.

## Decision: one tenancy unit, one projection seam

Skills follow the rules every owned resource in Metis follows
([`tenancy.md`](tenancy.md)):

    belongs_to :team

A user's personal team holds their "personal" skills. Authorization is
`skill.team.members.include?(current_user)` — the single expression,
no scope branching.

Projection is a single tree, `workspace/.pi/skills/`. Both sources
land there:

| Source | Mechanism |
|---|---|
| Repo `.pi/skills/` | Copied wholesale by `Workspace#stage_skills`. |
| Team's enabled `Skill` rows | Extracted to `workspace/.pi/skills/<slug>/` by the same method, after the repo copy. |

This is a per-turn projected input (like `uploads/`, `.mcp.json`,
`AGENTS.md`) — wiped + rewritten each turn, never archived. pi
auto-discovers skills from cwd, so loading the body when a skill
triggers happens through the same code path for repo and team
skills (and surfaces in the chat UI as a `read` tool call on
`SKILL.md`, relabelled to `skill: <name>` by
`ApplicationHelper#tool_call_display_name`).

### Why one tree, not two

An earlier version of this code split the two into sibling trees
(`.pi/skills/` for repo, `.pi/skills-db/` for team) and loaded team
skills via `pi --skill <path>`. It worked, but the asymmetry was
load-bearing in a bad way: `--skill` paths are pre-loaded into pi's
context at session start, so triggering one emits no `read` tool
call — team skill activation became invisible to the operator in
the chat UI, while repo skill activation showed up normally.

Merging into one tree restores parity: every skill, regardless of
source, gets the same lazy-load-on-trigger behaviour, and the same
UI surface.

### Repo isolation — why this is still safe

The agent can write *anywhere* under `workspace/.pi/skills/` during
a turn, including into a repo skill's directory. Four invariants
keep that from corrupting anything:

1. **The tree is wiped and re-copied from the repo at the start of
   every turn.** `stage_skills` does `rm -rf workspace/.pi/skills/`
   then `cp -r .pi/skills/` then writes team skills on top. Whatever
   pi did last turn — modify, delete, add files — is gone. The
   version pi sees is always pristine from git.

2. **Ingest filters by repo slug.** `Workspace#ingest_team_skills`
   walks the post-turn tree but skips any subdir whose name is a
   repo slug (`Agent::Workspace.repo_slugs`). Even if pi writes
   `.pi/skills/writing-rails-code/SKILL.md`, no team row is created
   from repo content.

3. **Model-level guard.** `Skill#slug_not_in_repo_tree` rejects any
   save where the slug matches a repo skill. The UI can't shadow a
   repo skill either.

4. **Provenance lives in the DB and in git, not on disk.** The
   workspace tree is a per-turn artefact; trying to encode "who
   authored this" in dir names was layering meaning on something we
   disposable.

### Frontmatter `name:` collisions

If a repo skill and a team skill declare the same `name:` in their
SKILL.md frontmatter (but different slugs), pi sees two skills with
the same name and picks one. Metis doesn't dictate which. Slug
collisions are prevented at save time (invariant 3 above), so
`name:` collisions are the only remaining ambiguity, and they only
arise if a team manually picks a `name:` that matches a repo
skill's `name:`. Treat as a teaming convention, not a technical
enforcement.

### Why team-only (not personal | space | system tiers)

Themis splits skills into `personal | space | system` with
override-by-name. It works, but it pushes a three-case branch into
every query, every authorization check, and every cache path. Metis's
team-of-one already collapses "personal" cleanly into the team model
([`tenancy.md`](tenancy.md)). The repo tree handles "system". That
leaves nothing for a third tier to do.

A real product gap shows up only when real-teams ships and a user
becomes a member of multiple teams: a "personal skill that follows
me into any team" can't be expressed in team-only. That tradeoff is
acknowledged and deferred to revisit alongside the real-teams
milestone — splitting into user+team scope at that point is a
mechanical migration.

## Model

```ruby
create_table :skills do |t|
  t.references :team, null: false, foreign_key: true
  t.references :created_by, foreign_key: { to_table: :users }
  t.references :updated_by, foreign_key: { to_table: :users }
  t.string  :slug, null: false
  t.string  :description
  t.text    :content_cache
  t.jsonb   :examples, default: []
  t.jsonb   :metadata, default: {}
  t.boolean :enabled, default: true, null: false
  t.timestamps
  t.index [:team_id, :slug], unique: true
end
```

- `slug` — kebab-case, becomes the directory name pi sees. Unique per
  team. Validated `/\A[a-z0-9\-]+\z/`.
- `description` — one-liner pi reads from frontmatter for
  auto-trigger. Surfaced in the index and the palette.
- `content_cache` — denormalized SKILL.md body so the index/palette
  does not stream blobs out of Active Storage on every render.
- `examples` — jsonb array of example prompts; rendered into the
  SKILL.md frontmatter on extract, surfaced in the UI.
- `metadata` — jsonb escape hatch for future frontmatter fields. No
  policy attached.
- `enabled` — soft toggle so a team can keep a skill around without
  projecting it.

```ruby
class Skill < ApplicationRecord
  belongs_to :team
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  has_many_attached :files

  SKILL_MD = "SKILL.md"

  validates :slug, presence: true,
                   uniqueness: { scope: :team_id },
                   format: { with: /\A[a-z0-9\-]+\z/ }

  scope :enabled, -> { where(enabled: true) }

  # The set of methods to port from themis (app/models/skill.rb):
  #   replace_skill_md!(content)
  #   replace_file!(relative_path, content, content_type = nil)
  #   refresh_content_cache!(tracked: false)
  #   extract_to(dir)
  #   relative_path(file)
  #   file_list
  #   text_file?(file) / editable_file?(file)
end
```

Files use Active Storage with a `metadata["relative_path"]` blob
field, so one skill row backs a *tree* of files (themis pattern).
`SKILL.md` is one of those files; `content_cache` mirrors it for fast
reads.

## Projection

Two methods, two destinations. Both per-turn projected input —
wiped + rewritten each turn, never durable.

```ruby
# Agent::Workspace#stage_skills — single tree, two sources
def stage_skills
  dest = skills_dir                                       # .pi/skills/
  FileUtils.rm_rf(dest)

  if SKILLS_SOURCE.directory?
    FileUtils.mkdir_p(dest.dirname)
    FileUtils.cp_r(SKILLS_SOURCE, dest)                   # repo tree first
  end

  team_skills = @conversation.team.skills.enabled
  return if team_skills.empty?

  FileUtils.mkdir_p(dest)
  team_skills.find_each { |s| s.extract_to(dest.join(s.slug)) }
end
```

`Local` and `Docker` use this directly (the host workspace is what
pi sees, either as cwd or via bind-mount). `E2b` mirrors the same
layout into the sandbox in `stage_skills(sandbox)`, uploading both
the repo tree and each enabled team skill to `WORKSPACE_DIR/.pi/skills/`.

Pi sees one tree and auto-discovers everything from cwd. The Pi
adapter doesn't pass any `--skill` flags.

## UI

Standard Rails resources, all Hotwire. No new JS surface.

**Routes.** `resources :skills` at top level. The team is implicit via
`current_team`; resources do not need to be nested.

**Controller.** Port the shape of themis's `SkillsController` minus
scope/checkout/zip-import (zip-import returns in Phase 4):

- `index/show/new/create/edit/update/destroy`
- `authorize_skill!` → `current_team.members.include?(current_user)`
- strong params: `:slug, :description, :enabled, :skill_md,
  examples: [], files: []`
- `skill_md` is the textarea-edited body of `SKILL.md`; the controller
  writes it via `Skill#replace_skill_md!`.

**Views.** Port from themis:

- `index.html.erb` — list, enable/disable toggle, pagy
- `_skill.html.erb` partial — single row, used by Turbo Stream
  broadcasts
- `_form.html.erb` — slug, description, SKILL.md textarea,
  examples (rows), file uploads
- `show.html.erb` — rendered SKILL.md, file tree, per-file inline
  editor for text files

**Broadcasting.** `after_commit` on `Skill` broadcasts to
`[team, :skills]` — append / replace / remove the `_skill` partial.
Mirrors `ChatBroadcaster`'s pattern; concurrent editors see updates
live.

**In-chat surface.**

1. Sidebar link to `/skills`.
2. "Skills" button in the composer opens `/skills` in a Turbo Frame
   modal. The user creates/toggles/edits in the modal; the next
   message they send picks up the changes via `stage_skills`.

No slash-command parser in v1 — a Turbo Frame modal is lighter and
more discoverable.

## What we explicitly drop from themis

Themis ships a richer system. The pieces we leave out, and why:

| Themis piece | Why dropped |
|---|---|
| `SkillExtractor` (~135 lines, cache dirs, atomic rename, mtime markers) | Metis already projects per-turn through `Workspace`. A second cache would duplicate that. |
| `SkillCheckoutService` + lock columns + `forked_from` | Last-write-wins for v1. Add when collaboration friction shows up. |
| `SkillToolBuilder` + ~13 `SkillTools::*` Rails tools | Themis's agent runs in-process with Ruby tool access. pi runs sandboxed; there is no Rails tool seam. Agent authoring is a different design — see below. |
| `personal | space | system` scope + three partial-unique indexes + visible_to/usable_by branching | Team-only collapses this. Repo tree handles "system". |
| PaperTrail versioning | Last-write-wins; SKILL.md frontmatter `version:` lives in the body if a team wants it. |
| Zip import | Deferred to Phase 4. |

This is roughly 60–70% less code than themis's skill stack, and the
agent gets skills live the next turn for free.

## Agent authoring

pi can create and modify team skills directly. The operator asks
in chat ("draft a skill for PR descriptions"); pi writes
`.pi/skills/<slug>/SKILL.md` (and supporting files) in its own
workspace; Metis syncs them back to the team's `skills` rows when
the turn ends.

The convention is taught to pi in `AGENTS.md` (see
`Agent::Identity`): write skills at `.pi/skills/<slug>/SKILL.md`
with YAML frontmatter (`name`, `description`) plus a markdown body
of instructions. Supporting files alongside SKILL.md are kept. Repo
skills are read-only — their slugs are reserved and any writes to
them are wiped by the next turn's `stage_skills`.

### The signal: pi's own tool events

Ingest is **event-driven, not scan-driven**. As pi streams tool
events to the adapter (`Agent::Adapters::Pi#translate`), every
`tool_execution_end` event for `write` / `edit` / `bash` is
inspected:

- `write` / `edit` — `args.path` matched against `.pi/skills/<slug>/`.
  Match → `@runtime.note_skill_touched(slug)`.
- `bash` — `args.command` regex-scanned for the same path shape (the
  agent might `cat > .pi/skills/.../SKILL.md` or `cp`/`mv` between
  skill dirs). Every match recorded.

The runtime accumulates a `Set<slug>` across the turn. When the
turn ends, the runtime's ingest method iterates exactly those
slugs — no whole-tree scan, no mtime check, no I/O for untouched
skills. Same code on Local, Docker, and E2b.

`Agent::Workspace#ingest_team_skills(slugs:, by:)`:

- For each slug in the set:
  - Skip if the slug is a repo skill (`Agent::Workspace.repo_slugs`)
    — repo-named writes never produce a team row.
  - Skip if the slug doesn't match `[a-z0-9][a-z0-9\-]*`.
  - Call `ingest_team_skill_from_files(slug:, files:, by:)` (the
    runtime-agnostic DB upsert) with the file map.

`ingest_team_skill_from_files` is the DB-side; it works from an
in-memory `{rel_path => bytes}` map so it doesn't care whether the
files came from disk or a sandbox `read`:

- `find_or_initialize_by(slug:)`, set `created_by`/`updated_by`.
- Re-parse `description` from the SKILL.md YAML frontmatter.
- Identical-body short-circuit: if `content_cache == body` and
  nothing else changed, return without touching the row (a `touch`
  without content change is a no-op).
- Otherwise: purge attached files, save, re-attach each file under
  its relative path. Mirrors to `content_cache`.

**Upsert-only — no auto-delete.** A row is never deleted just
because its slug wasn't in this turn's touched set. That keeps
destructive operations in the operator's hands (delete from the
UI), and dodges the disabled-skill edge case: a disabled skill
isn't staged, so its absence from disk is normal, not a delete
signal.

**Bash escape hatch.** The bash regex is a *heuristic* — the same
heuristic the activity log uses to relabel `bash` calls as
`skill: <name>`. An agent that writes to a SKILL.md via a subshell
script (`bash python script.py`) where the path doesn't literally
appear in the command bypasses ingest. The fix is to ask the
operator to recreate the skill from the UI, or for pi to add a
proper file-write hook upstream.

**Conflict with concurrent UI edits.** Last write wins. If a human
saves a skill in `/settings/skills` while a turn is running, the
turn's ingest may overwrite the human's edit (or vice-versa). v1
accepts this; if friction shows up, layer in the themis
checkout/lock pattern.

### Per-runtime coverage

| Runtime | Ingest path |
|---|---|
| `Local` | Workspace reads from host disk. |
| `Docker` | Same — the container bind-mounts the host workspace. |
| `E2b` | Runtime lists + reads each touched slug's dir from the sandbox via the E2B SDK (`sandbox.files.list` + `sandbox.files.read`), builds the file map, calls `Workspace#ingest_team_skill_from_files`. One list RPC + one read per file in the dir — no walk of untouched skills. |

## Open questions

1. **Sharing across teams.** How does "build a tool and share it"
   work for skills — export/import, a hosted registry, git-backed?
   Same question PLAN.md open-question #2 raises for connectors and
   extensions. Same answer should apply to all three.
2. **Frontmatter contract.** SKILL.md frontmatter today carries
   `name` + `description`. Themis adds `version`, `examples`. What
   becomes a first-class column (rendered by Metis) vs. an arbitrary
   passthrough in `metadata`?
3. **System skills' source of truth.** Today repo's `.pi/skills/` is
   read-only from Metis. If a team forks a system skill — copy into
   the team scope, or first-class "override" with a back-reference?
   v1 punts: a team can create a same-slug skill and override
   projection.
