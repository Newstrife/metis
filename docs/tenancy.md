# Tenancy & ownership

## Context

Metis is multi-user; personal and team usage are both first-class
([`VISION.md`](../VISION.md) — *Multi-user from day one*). Every
durable resource — conversations, connectors, projects, skills —
needs an owner, and the same question recurs for each: *may this
user see, use, or manage it?*

This doc records how that is modelled. "Workspace" is deliberately not the
word: `Agent::Workspace` already names pi's per-conversation scope
directory. The tenancy unit is the **team**.

## Decision: one tenancy unit — the team

There is a single tenancy unit, `Team`. A **personal account is a team of
one** — every user gets a personal team at signup, of which they are the
sole member.

Every ownable resource carries one foreign key:

    belongs_to :team

`Membership(user, team, role)` is the single authorization primitive, so
"may this user touch this resource?" is always one expression, with no
`User`-vs-`Team` branch:

    resource.team.members.include?(user)

### Why not a polymorphic owner

The alternative is `belongs_to :owner, polymorphic: true` — a `User` or a
`Team`. It looks DRY, but it does not remove the `User`/`Team`
distinction; it pushes a two-case branch into every policy and every scope
of every resource, permanently. A team of one collapses that branch to
nothing.

It is also the better product model. A personal team that gains a second
member simply *becomes* a shared team — an upgrade, not a migration. The
cost is small and honest: a `Team` row per signup and a `team_id` on
resources that feel personal; a `personal:` flag lets the UI hide the team
framing for solo users.

## Resources are composed into a conversation

Ownership is half the model. The other half: a conversation is a
**composition point**. Owned resources are attached to a conversation and
projected into the pi runtime once per turn.

| Resource  | Owned via            | Projected into the runtime as |
|-----------|----------------------|-------------------------------|
| Connector | `belongs_to :team`   | `.mcp.json` — see `connectors.md` |
| Project   | `belongs_to :team`   | repo + tracker context — see below |
| Skill     | `belongs_to :team`   | `pi --skill` paths |
| Upload    | `Message` attachment | `workspace/uploads/` — see `session-persistence.md` |

The shape is flat — resources are not nested inside one another. A
conversation references the resources it uses; the runtime projects them
each turn. A new resource type joins by following the same two rules:
owned through a `Team`, projected per turn.

## Projects

A `Project` is a named **R&D context**. A user creates one and binds it to
external systems — a GitHub repository, a Linear project — so that a
conversation pointed at the project works against that repo and that
tracker.

A Project is **configuration, not a filesystem**. Its durable state lives
in the external systems — the repo on GitHub, the issues in Linear — not
in a Metis-owned store. The agent reaches them through their MCP
connectors and writes back via git, pull requests, and Linear's own tools.
The conversation's `workspace/` stays a per-conversation working clone, so
`session-persistence.md` is unaffected.

A Project therefore sits **on top of connectors**. GitHub and Linear are
MCP connectors — capability plus credential. The Project is the *binding*
that scopes them to one repo and one tracker and bundles them as a named
context. A Project references connectors; it does not re-implement their
auth.

Projects are user-managed for now. Under team-of-one that is already
team-aware — a user's project is owned by their personal team — so
team-shared projects arrive later with no migration.

## Open

- **`Project` ↔ conversations (1:N).** Whether a project owns a set of
  conversations is undecided. It is purely additive when it lands — a
  nullable `project_id` on `Conversation`, or a join table — so deferring
  it carries no migration risk.
- **Connecting a repo.** Whether "connect a GitHub repo" picks an
  already-authorized connector or triggers connector OAuth at that moment
  is an open UX decision.
- **Teams beyond team-of-one.** How shared teams are created, joined, and
  (if hosted) billed — see PLAN.md open questions.
