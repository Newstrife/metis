---
name: writing-rails-code
description: Metis-specific Rails 8.1 coding conventions — models, controllers, services, jobs, and comments. Use when writing or modifying Ruby/Rails code in the Metis repository.
---

# Writing Rails Code in Metis

Metis is a Rails 8.1 web app (Ruby 4.0.5, PostgreSQL) with Hotwire +
Devise that puts a chat UI in front of the pi agent. See `CLAUDE.md`
and `VISION.md` for the architecture and the "won't build" rules; this
skill covers day-to-day code conventions.

## Models

- Ordering: enums, associations, attached fields, encryption,
  validations, scopes, public methods, private methods.
- **Tenancy is `Team`-only.** Every ownable resource declares
  `belongs_to :team` and is authorized through `resource.team.members`.
  No polymorphic `owner`, no `User`-vs-`Team` branch. See
  `docs/tenancy.md`.
- Enums are integer-backed with explicit mappings:

  ```ruby
  enum :role, { user: 0, assistant: 1, tool: 2, system: 3 }
  enum :streaming_status, { pending: 0, streaming: 1, done: 2, errored: 3, canceled: 4 }
  ```

- Sensitive text uses Active Record encryption — see
  `Message#encrypts :content, :reasoning`. Encryption keys must be
  present in every environment that touches the model (set for tests in
  `config/environments/test.rb`).
- Scopes for every common query — no inline `where` chains in
  controllers or jobs.
- jsonb columns (`Conversation#settings`, `#agent_model`,
  `#runtime_state`) are read directly (`conv.settings["model"]`). Skip
  `store_accessor` unless a field needs Active Model coercion or
  validation.
- Use `normalizes` for whitespace-stripping form inputs — see
  `User#normalizes` on the profile fields.
- Use validation contexts (`on: :profile_update`) when validation
  should fire only for a specific flow, not on every write.

## Controllers

- All controllers inherit `ApplicationController`, which runs
  `authenticate_user!`, locale, and timezone wrappers — skip them only
  on Devise or genuinely-public endpoints.
- Strong params for every create/update. Never permit a hash directly
  off `params`.
- Delegate business logic to services or model methods. Controllers
  are dispatch + persistence + response — not the place for domain
  logic.
- Dual-format actions use `respond_to`:

  ```ruby
  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to @conversation }
  end
  ```

- Shared composer-like behavior belongs in
  `app/controllers/concerns/`. See `Composing`, mixed into both
  `MessagesController` and `ConversationsController`.

## Services

- Plain Ruby classes in `app/services/`, namespaced when they
  cluster (`Agent::`, `OauthBroker::`, `GithubApp::`).
- Constructor injection for dependencies (`conversation`,
  `runtime_kind`, …).
- The Agent service layer is the core of the app — see CLAUDE.md.
- A service that renders a per-turn projected input
  (`Agent::Identity`, `Agent::McpConfig`) is rebuilt from durable
  Rails records every turn. Never persist its output to the workspace
  as durable state.

## Jobs

- Inherit `ApplicationJob`, use `queue_as :default`. Solid Queue runs
  jobs in production.
- Long-running jobs should rescue `StandardError`, log, and stamp
  their tracking record `failed` — don't let the UI hang on a silent
  error.
- **Reload before the recovery write.** In-memory dirty attributes
  from a failed persist can poison the rescue update (e.g., a
  `tool_calls` bag with a U+0000 byte that Postgres rejected). See
  `ChatJob#fail_message` for the canonical pattern.
- Broadcast the failure too, when a UI is waiting on it
  (`broadcaster.fail`, `broadcaster.refresh_composer`).

## Comments

Ruby is read-aloud. Good code names what it does — comments that
duplicate that just add noise. **Default to no comment.** Add one
only when the code can't speak for itself.

**Write a comment when**

- **Why, not what**: a non-obvious decision, constraint, gotcha, or
  external-API quirk the code can't show on its own.
- **Public API contract**: inputs/outputs/side effects on a class or
  public method another file consumes (especially `app/services/`).
- **Magic constant**: a number or string with hidden semantics (TTL
  boundary, protocol version, regex intent).
- **`TODO` with a ticket**: `# TODO(FLA-123): ...`. Bare `TODO` rots.

**Do NOT comment when**

- **You're restating the code**: `# Archive the conversation` above
  `def archive!` — the name already says it.
- **You're explaining another file's mechanics**: how `ChatBroadcaster`
  consumes this, how `MessagesController` calls in — those narratives
  belong in CLAUDE.md, skill docs, or the commit message. Inline they
  go stale the first time the caller changes.
- **You're justifying the design**: "Mirrors X so Y can register
  without bespoke wiring." If the design needs that much defending,
  refactor it or write a doc.
- **You're annotating a kwarg**: a 5-line preamble explaining what
  `runtime_kind:` means → name the parameter clearly and trust the
  caller to be the proof.
- **You're labeling sections**: `private` already says "private
  methods". No `# ===== helpers =====` banners.
- **You're stating the obvious**: `# Initialize the user`, `# Loop
  through results`, `# Return the value`.
- **You're parking dead code**: delete it. Git remembers.

**Style**

- Sentence case, full sentences end with a period.
- Single `#` then one space.
- Keep to ≤2 lines. If you need more, the code or naming is the
  problem.
- No YARD tags (`@param`, `@return`) — we don't generate docs from
  them.
- No ASCII banners, no decorative `####` rows.

**The earn-its-place test**

Read the comment, delete it, re-read just the code. Lost information?
Keep it. Otherwise it was noise.

## For detailed reference

- **Testing with Minitest**: see [TESTING.md](TESTING.md)
- **Hotwire / Turbo / Stimulus patterns**: see [HOTWIRE.md](HOTWIRE.md)
