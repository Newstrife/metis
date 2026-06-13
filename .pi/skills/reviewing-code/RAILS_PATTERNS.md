# Rails Anti-Patterns to Catch in Reviews

## N+1 Queries

```ruby
# BAD: N+1 — loads each project's agent_runs individually
projects.each { |p| p.agent_runs.count }

# GOOD: Eager load or use counter cache
projects.includes(:agent_runs).each { |p| p.agent_runs.size }
```

## Fat Controllers

```ruby
# BAD: Business logic in controller
def create
  @review = Review.new(review_params)
  github = GithubAPIService.new
  github.create_pull_request_review(...)
  @review.save!
end

# GOOD: Delegate to service/workflow
def create
  workflow = Workflows::PRReviewWorkflow.new(options: build_options)
  workflow.execute(repo: repo, pr_number: pr_number)
end
```

## Missing Error Handling in Workflows

```ruby
# BAD: No status tracking on failure
def execute
  result = run_agent(prompt: prompt)
  agent_run.complete!(result)
end

# GOOD: Rescue and record failure
def execute
  result = run_agent(prompt: prompt)
  agent_run.complete!(result)
rescue => e
  agent_run.fail!(e.message)
  raise
end
```

## Unsafe JSONB Queries

```ruby
# BAD: String interpolation in JSONB query
where("data->>'#{key}' = '#{value}'")

# GOOD: Parameterized
where("data->>? = ?", key, value)
```

## Missing Test Coverage

Flag PRs that add:
- New model without model test
- New service without service test
- New controller action without controller/integration test
- Changed business logic without updated tests

## Turbo Stream Issues

- Missing `format.html` fallback alongside `format.turbo_stream`
- Broadcasting to wrong stream name (must match subscription)
- DOM ID mismatches between `target:` and actual element IDs

## Job Patterns

- Jobs should be idempotent (safe to retry)
- Long-running jobs should update status records for UI feedback
- Jobs should not call other jobs synchronously (`perform_now` chains)
