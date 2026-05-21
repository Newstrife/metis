# Single Coding-Agent Foundation

## Decision

Metis is built on **one coding-agent foundation** and integrates with it
deeply. It will not become a generic adapter layer that wraps multiple
interchangeable coding-agent backends (pi, Claude Code, Codex, …).

## Mission

Metis stands on the open agent world with a philosophy of **purity and
simplicity**. It is an opinionated product, not a neutral switchboard —
and it is meant to be more than a coding-agent chat window.

Its trajectory is to grow into a strongly-opinionated **multi-agent
platform**. That phrase needs care, because it is easily confused with
the thing this document rejects:

- **Multi-agent platform** — a product where agents are first-class:
  orchestration, specialized sub-agents, an agentic experience built
  *on* a single foundation. This is the goal.
- **Multi-coding-agent shell** — a UI that abstracts over several
  coding-agent CLIs so any of them can be swapped in. This is *not* the
  goal, and never was.

The first is depth. The second is breadth bought with depth.

## Why not a multi-coding-agent shell

A shell needs a canonical, backend-agnostic vocabulary (in Metis, that is
`Agent::UiEvent`). A canonical vocabulary is a **lowest common
denominator** — fine for a thin product (stream text, show tool calls),
but it works against everything that makes an agent product valuable.

The features that matter — skills, MCP, sub-agents, hooks, checkpointing,
permission models, collaboration — are **not uniform across agents**.
Each new feature forces one of two bad outcomes:

- **Genericize it** → the feature collapses to the weakest form every
  backend can support. The product gets blander as it grows.
- **Special-case it** → `if backend == …` branches leak through the
  abstraction into jobs, views, and controllers. The abstraction stops
  paying rent: you maintain the indirection *and* the per-backend code.

So the value of a multi-adapter layer runs **backwards**: highest when
the product is simplest, lowest exactly as the product gains the features
that would justify it.

A feature-rich agentic product is a **vertical integration** with one
agent's runtime and SDK. Deep and agent-neutral cannot both be true.

### Evidence

Themis — a sibling product — is feature-rich: MCP servers, skills,
sub-agents, hooks, permissions, checkpointing. It did **not** build a
multi-adapter abstraction. It committed to one agent SDK and exploited it
natively. That is the shape a serious agent product takes.

## Consequences

- **The single foundation gets all the depth.** Skills, MCP, sub-agents,
  collaboration — integrated natively against one agent's capabilities,
  never flattened to a portable subset.
- **`Agent::Adapters` / `Agent::UiEvent` stay — as internal decoupling.**
  Keeping the chat UI ignorant of the agent's wire protocol is sound
  layering on its own merits. They are not a product surface, not a
  promise of pluggable backends, and not a roadmap item.
- **No second coding-agent adapter is built on spec.** Adding one is
  revisited only on concrete, specific pull — never as a matter of
  principle or "optionality."
- **The `Runtime` axis (Local / E2b) stays.** *Where* the agent runs is
  genuinely orthogonal — it carries no lowest-common-denominator cost —
  and microVM isolation is real product value.

## In one line

Metis is an opinionated multi-agent platform on one open coding-agent
foundation — not a generic shell over many.
