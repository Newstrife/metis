# Security Checklist for PR Reviews

## Authentication & Authorization

- [ ] All new endpoints require `authenticate_user!` (inherited from ApplicationController)
- [ ] Webhook endpoints verify signatures instead of user auth
- [ ] User can only access their own resources (scoped queries: `current_user.conversations.find(id)`)
- [ ] No direct `Model.find(params[:id])` without ownership check for user-scoped data

## Input Validation

- [ ] Strong params whitelist all allowed attributes
- [ ] JSONB fields use parameterized queries, not string interpolation
- [ ] User input is sanitized before rendering (Rails auto-escapes in ERB, but watch `raw`/`html_safe`)
- [ ] File uploads validate content type and size

## Credential Safety

- [ ] Secrets use `Rails.application.credentials`, never hardcoded
- [ ] No credentials in logs, error messages, or API responses
- [ ] Test files stub credentials, never use real tokens
- [ ] `.env` files and credential files are in `.gitignore`

## SQL & Data

- [ ] No raw SQL with user input — use parameterized queries or ActiveRecord
- [ ] JSONB queries use `->?` parameter binding, not string interpolation
- [ ] Bulk operations use transactions where atomicity matters

## Agent & MCP Security

- [ ] Agent tools have appropriate permission boundaries
- [ ] File access restrictions enforced (no reading `.env`, credentials, etc.)
- [ ] Code generation runs in isolated worktrees, not the main repo
- [ ] PR creation uses branch prefixes to avoid overwriting user branches

## Common Rails Pitfalls

- [ ] No `skip_before_action :verify_authenticity_token` without good reason
- [ ] No `html_safe` on user-provided content
- [ ] No `send(params[:method])` or other dynamic dispatch with user input
- [ ] No `eval`, `instance_eval`, or `class_eval` with external data
