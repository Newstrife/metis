---
name: reviewing-code
description: Code review methodology — security checklist, Rails anti-patterns, review quality standards. Use when reviewing pull requests or generating PR review feedback.
---

# Reviewing Code

## Review Methodology

1. **Understand the change** — Read the PR description and all commits, not just the diff
2. **Check for regressions** — Does the change break existing behavior?
3. **Verify test coverage** — New code should have tests; changed code should have updated tests
4. **Review security** — See [SECURITY_CHECKLIST.md](SECURITY_CHECKLIST.md)
5. **Check Rails patterns** — See [RAILS_PATTERNS.md](RAILS_PATTERNS.md)
6. **Spot simplification opportunities** — See [SIMPLIFICATION.md](SIMPLIFICATION.md)
7. **Read previous discussion** — Never re-raise issues already addressed in PR comments

## Review Verdicts

- **APPROVE**: Code is correct, tested, and follows patterns. Minor style nits are not blocking.
- **COMMENT**: Questions or suggestions that don't block merging.
- **REQUEST_CHANGES**: Bugs, security issues, missing tests, or architectural problems.

## Comment Quality

Good review comments:
- Explain the *why*, not just the *what*
- Suggest concrete fixes, not vague criticism
- Distinguish blocking issues from suggestions (prefix non-blocking with "nit:" or "suggestion:")
- Reference specific lines and files

Bad review comments:
- "This looks wrong" (no explanation)
- Nitpicking style when there's no project convention
- Requesting changes unrelated to the PR's scope
- Repeating what linters already catch

## Confidence Scoring

Score each issue 0-100 before including in your review:
- **90-100**: Definite bug, security vulnerability, data loss risk
- **80-89**: Very likely issue — missing error handling, race condition, N+1 query
- **60-79**: Probable but context-dependent — verify via codebase tools before including
- **Below 60**: Style nit or uncertain — omit

Only report issues scoring **80+**. For 60-79 scores, use Read/Grep on the local codebase to verify the issue is real before including it.

## Summary Format

The review summary should include these sections:

### Review Summary
**Status: [VERDICT]**

[2-3 sentence overview of what the PR does and your overall assessment]

### Key Issues Identified
1. **[Issue Title]** (confidence: N)
   [Explanation of why it matters and potential impact]

### Positive Aspects
- **[Aspect]**: [Brief explanation]

### Recommendations
[Action items or confirmation of merge readiness]

## Output Format

Use the `submit_review` tool with your verdict, summary, and inline comments. Do not output raw JSON.

## Simplification Opportunities

Flag code that does the right thing but does too much of it. These are usually `suggestion:` (non-blocking) unless complexity is masking a bug.

- **Duplication** — same logic in 2+ places. Suggest a shared method/concern only if duplication is exact and likely to drift.
- **Defensive code on internal boundaries** — `try`, `&.`, `nil?` checks, or `rescue` for values guaranteed by the caller or framework. Trust internal guarantees; validate only at system boundaries (user input, external APIs).
- **Premature abstraction** — single-caller helpers, one-method service objects, parametrized methods with one real call site. Three similar lines is better than the wrong abstraction.
- **Dense one-liners** — chained `map.select.reject.group_by` that needs a comment to read. Prefer explicit intermediate variables.
- **Nested conditionals / ternaries** — flatten with guard clauses, early returns, or case statements.
- **Restating-code comments** — comments that paraphrase what the next line obviously does. Only the *why* (non-obvious constraint, workaround, surprise) earns a comment.
- **Backwards-compat shims for unreleased code** — feature flags, fallbacks, or `# removed` placeholders for code paths nothing in production calls yet.
- **Error handling for impossible states** — validating things the type system or DB constraint already enforces.

When suggesting simplification: show the rewrite, don't just describe it. See [SIMPLIFICATION.md](SIMPLIFICATION.md) for concrete before/after examples.

What *not* to flag as simplification:
- Removing helpful abstractions because they have one caller *today* but a clear second caller incoming
- Collapsing readable multi-line code into a clever one-liner
- Removing comments that explain *why* (constraints, workarounds, invariants)
- Style preferences with no project convention behind them

## Prompt Smell

Flag these in PRs that modify prompt files (`app/prompts/`, SKILL.md descriptions):

- **Emphasis abuse**: `NEVER`/`ALWAYS`/`MANDATORY`/ALL CAPS — the agent architecture should enforce behavior, not the prompt's volume
- **Hardcoded names in shared prompts**: Feature-specific skill names, tool names, or business logic in generic templates like `base_agent.md.erb` — should be dynamic (ERB conditional, metadata-driven)
- **Prompt bloat**: Adding >5 lines to a shared prompt for a single feature — should it be conditional, a partial, or handled structurally?
- **Scaling test**: "If we add 5 more of these, does the prompt still work?" If the pattern requires editing the base prompt for each new instance, it's the wrong approach
- **Rhetorical fixes for structural problems**: Adding instructions like "do NOT use tool X, use tool Y instead" — this is a routing/priority problem that should be solved with metadata, tool design, or configuration

## For Detailed Reference

- **Security checklist**: See [SECURITY_CHECKLIST.md](SECURITY_CHECKLIST.md)
- **Rails anti-patterns to catch**: See [RAILS_PATTERNS.md](RAILS_PATTERNS.md)
