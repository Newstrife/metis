# Simplification Patterns to Catch in Reviews

Flag the *signal* — code that does too much — and propose a concrete rewrite. These are usually `suggestion:` (non-blocking). Promote to `REQUEST_CHANGES` only when complexity is hiding a bug or violating Metis conventions.

## Defensive Code on Internal Boundaries

```ruby
# BAD: nil-checking a value the caller already validated
def deliver(message)
  return unless message
  return unless message.conversation
  message.conversation.broadcast(message.body)
end

# GOOD: trust the caller; fail loudly if assumptions break
def deliver(message)
  message.conversation.broadcast(message.body)
end
```

Apply to: `&.` chains, `try`, `rescue` around internal service calls, `presence` on values that can't be blank.

## Premature Abstraction

```ruby
# BAD: one-method service object with a single caller
class Reviews::CommentFormatter
  def self.format(comment)
    "#{comment.author}: #{comment.body}"
  end
end

# GOOD: inline it
"#{comment.author}: #{comment.body}"
```

Three similar lines is better than the wrong abstraction. Extract when the *third* caller appears, not the first.

## Restating-Code Comments

```ruby
# BAD
# Find the user by ID
user = User.find(params[:id])

# Increment the counter
counter += 1

# GOOD: only comment the *why*
# GitHub returns 422 on self-review, so downgrade to COMMENT
verdict = "COMMENT" if self_review?(pr)
```

Per the global preferences: only comment when removing it would confuse a future reader.

## Dense One-Liners

```ruby
# BAD: chain that needs a comment to read
recent = msgs.select { |m| m.created_at > 1.day.ago }.group_by(&:user_id).transform_values { |ms| ms.max_by(&:created_at) }.values

# GOOD: name the steps
recent_messages = msgs.select { |m| m.created_at > 1.day.ago }
latest_per_user = recent_messages.group_by(&:user_id)
latest_per_user.values.map { |ms| ms.max_by(&:created_at) }
```

Clarity over brevity.

## Nested Conditionals

```ruby
# BAD
def status
  if agent_run.present?
    if agent_run.completed?
      if agent_run.output.present?
        "done"
      else
        "empty"
      end
    else
      "running"
    end
  else
    "pending"
  end
end

# GOOD: guard clauses, flat structure
def status
  return "pending" if agent_run.nil?
  return "running" unless agent_run.completed?
  agent_run.output.present? ? "done" : "empty"
end
```

## Backwards-Compat Shims for Unreleased Code

```ruby
# BAD: feature flag for code nothing in production calls yet
def deliver
  if Flipper.enabled?(:new_delivery_path)
    new_path
  else
    legacy_path
  end
end

# GOOD: just write the new path
def deliver
  new_path
end
```

Per the global CLAUDE.md: don't use feature flags or compat shims when you can just change the code. Flag any `# removed`, `# deprecated`, or renamed `_unused` placeholders left behind.

## Validating Impossible States

```ruby
# BAD: DB has NOT NULL constraint + presence validator on user_id
def perform(message)
  return unless message.user_id
  ...
end

# GOOD: trust the schema
def perform(message)
  ...
end
```

Validate at system boundaries (params, webhook payloads, external API responses) — not on values produced by your own DB or service layer.

## Duplication

Flag exact duplication across services/jobs (e.g., the same image-download + content-type check in three places). Extract to a concern or service object only when:

- The duplication is exact (not "similar shape")
- The logic is likely to drift if left duplicated (security, formatting, business rules)
- There are 3+ call sites — two is usually fine

For 2 call sites of similar-but-not-identical logic, leave it duplicated. Forced extraction creates worse problems than it solves.

## Over-Rescue

```ruby
# BAD: swallowing real errors
def fetch_pr
  GithubAPIService.new.get_pull_request(repo, number)
rescue => e
  Rails.logger.warn("Failed: #{e.message}")
  nil
end

# GOOD: rescue specific errors at the boundary, let others propagate
def fetch_pr
  GithubAPIService.new.get_pull_request(repo, number)
rescue Octokit::NotFound
  nil
end
```

Per the global preferences: pragmatism — let unknown errors hit Sentry; don't smother them.

## What *Not* to Flag

- Removing a one-caller helper that has an obvious second caller incoming in a follow-up PR
- Multi-line code that's already clear — don't compress it
- Comments explaining *why* (constraints, workarounds, surprising behaviors)
- Style preferences without a project convention behind them
- "Could be one line" suggestions when the multi-line version reads better
