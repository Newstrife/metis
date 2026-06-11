---
name: writing-spec
description: Write an implementation spec as a workflow step — the self-contained brief a coding agent (often on a teammate's machine) implements and a later review step verifies. Use when a workflow step asks you to write, design, or revise a spec for a change.
---

# Writing a spec inside a workflow

Your spec is a step in a gated workflow, and three different readers
consume it:

1. **Reviewers at the gate** — humans who approve, or send it back with
   feedback, possibly several rounds. They read fast; structure for
   skimming and decisions.
2. **The implementer** — a coding agent, often on a teammate's machine
   via the local bridge. It receives your spec as its *entire brief*:
   no session, no chat history, no chance to ask you anything. It will
   implement exactly what is written — every gap becomes its guess, and
   a wrong guess costs a full gate-and-redispatch round trip.
3. **The review step** — a later cloud turn that checks the resulting
   PR *against your spec*. Every requirement you state will be
   verified; anything vague is unverifiable and therefore unenforced.

**Completeness beats brevity.** The spec travels to the implementer in
full, so write what correctness requires — but spend the length on
substance, not padding: a reviewer still has to hold it in their head.

## The closed-world test

Before gating, reread the spec pretending you've never seen this
conversation and have only the spec plus a checkout of the repo. The
repo gives the implementer code, conventions (CLAUDE.md / AGENTS.md),
and existing patterns — your spec must supply everything else:

- **Intent** — what the user gets and why it's wanted.
- **Decisions already made** — choices from the incubation rounds and
  rejected alternatives, so the implementer doesn't relitigate them.
- **Hidden constraints** — invariants and guardrails that are not
  visible in the code (security boundaries, "we deliberately don't…",
  deploy-window concerns, product promises).
- **Exact contracts** — data shapes, payloads, state transitions, error
  paths, user-facing copy. Write them precisely (real JSON keys, real
  enum values, verbatim strings), not as prose.
- **Anchors into the repo** — real file paths, class/method names, and
  an existing exemplar to imitate when one exists ("mirror how
  `approve_current_gate!` re-enters the engine"). Verify the names
  exist before writing them down.

If a question is still open, do not hand off ambiguity: either resolve
it and record the decision, or state the default you chose and why —
the gate reviewer can overrule it cheaply; the implementer can't.

## Shape

Use these sections in this order, skipping any that are genuinely
empty:

```markdown
# Spec: <one-line title>

**Repo**: `owner/name` — one clause on stack and where conventions live.

## Goal
What changes for the user and why. Intent, not mechanism.

## Context & decisions
What the implementer can't recover from the repo: choices made at the
gates, rejected alternatives, hidden constraints, relevant history.

## Requirements
Numbered, declarative, individually verifiable:
R1. …
R2. …
Every "should" is a requirement — write it as one or cut it.

## Approach
Files/touchpoints and what happens in each; exemplars to follow.
Behavior and seams, not method bodies — code only at signature level.

## Interfaces & data
Exact request/response examples, schema or jsonb shapes, enum values,
user-visible copy verbatim.

## Edge cases
Each one paired with its expected behavior — an edge case without a
decision is an open question in disguise.

## Out of scope
What an eager implementer might do that you explicitly don't want.

## Acceptance
How the review step verifies each requirement: runnable commands
(lint, tests, curl) and observable behaviors, ideally mapped R-by-R.
```

Numbered requirements with mapped acceptance are what make the chain
work end to end: the implementer builds to R1–Rn, the reviewer ticks
R1–Rn against the diff, and nothing rides on shared memory.

## Rules

- **Self-contained or it doesn't exist.** Never write "as discussed
  above" or lean on chat context — inline whatever matters.
- **Stay at spec altitude.** Describe behavior and contracts, not
  implementations. If you're writing method bodies, you're doing the
  implementer's step — except where exactness *is* the requirement
  (payloads, copy, shapes), where verbatim is correct.
- **Expect to be revised.** When the gate sends feedback, rewrite the
  spec in place as a clean next version — fold the feedback in; don't
  append a changelog or argue with the review.
- **Right-size the ask.** One spec, one landable PR. If the goal needs
  more, spec the first slice and name the rest in Out of scope.

## When you publish

Emit the full spec as your message body — it travels to the
implementer whole, and is the version the gate reviews. Also saving it
as a file artifact (`<kebab-title>-spec.md`) is welcome for download,
but the message text is the source of truth.
