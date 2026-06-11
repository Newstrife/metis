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
   no session, no chat history, no chance to ask you anything. If a fact
   isn't in the spec, the implementer doesn't have it.
3. **The review step** — a later cloud turn that checks the resulting
   PR *against your spec*. Every requirement you state will be verified;
   every vague wish will be unverifiable.

## Shape

Keep it under ~40 lines of markdown. Use exactly these sections, in
this order, skipping any that are genuinely empty:

```markdown
# Spec: <one-line title>

**Repo**: `owner/name` — one clause on stack and where conventions live
  (CLAUDE.md / AGENTS.md).

## Goal
What changes for the user, in 2-3 sentences. The why, not the how.

## Approach
The files you expect to touch and what happens in each — a short list,
not code. Name real paths and real identifiers; if you haven't checked
they exist, check before writing them down.

## Edge cases
Only ones that change the implementation. No generic hand-waving.

## Out of scope
What an eager implementer might do that you explicitly don't want.

## Verification
Concrete, runnable acceptance: the commands (lint, tests, a curl), and
the observable behaviors a reviewer can check on the PR diff.
```

## Rules

- **Self-contained or it doesn't exist.** Never write "as discussed
  above", "per the previous step", or reference chat context — the
  implementer sees only the spec text. Inline whatever matters.
- **Name real things.** Repository, branch convention, file paths,
  class/method names, env vars. A spec that says "the relevant model"
  forces the implementer to guess; a wrong guess costs a full
  gate-and-redispatch round trip.
- **Make acceptance checkable.** "Works correctly" is not verifiable;
  "`bin/rails test` green and the new endpoint returns 409 for a claimed
  task" is. Write the Verification section for the review step that will
  hold the PR against it.
- **Stay at spec altitude.** Describe behavior and touchpoints, not
  implementations — no code blocks longer than a signature. If you're
  writing method bodies, you're doing the implementer's step.
- **Expect to be revised.** When the gate sends feedback, rewrite the
  spec in place as a clean next version — fold the feedback in; don't
  append a changelog or argue with the review.
- **Right-size the ask.** A spec the implementer can land as one PR. If
  the goal needs more, say so in Out of scope and spec the first slice.

## When you publish

Emit the spec as your message body (it travels to the implementer in
full). If you also save it as a file artifact, name it
`<kebab-title>-spec.md` — but the message text is the source of truth.
