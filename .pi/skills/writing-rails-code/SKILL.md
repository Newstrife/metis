---
name: writing-rails-code
description: Rails 8.1 coding conventions — models, controllers, services, jobs, Hotwire, and Minitest patterns. Use when writing or modifying Ruby/Rails code in this repository.
---

# Writing Rails Code

## Rails Conventions

### Models

- Validations first, then associations, then scopes, then methods
- Use `store_accessor` for JSONB flexible settings (not individual columns)
- Define enum-like status fields as string arrays with explicit state transitions
- Scopes for every common query — never inline `where` chains in controllers

```ruby
class Project < ApplicationRecord
  has_many :agent_runs, dependent: :nullify
  validates :owner, presence: true
  validates :name, presence: true, uniqueness: { scope: :owner }
  store_accessor :agent_settings, :language, :tone, :persona
end
```

### Controllers

- `before_action :authenticate_user!` inherited from ApplicationController
- Strong params for all create/update actions
- Turbo Stream responses for dynamic updates: `respond_to { |f| f.turbo_stream { ... } }`
- JSON endpoints for AJAX data fetching (e.g., `render json: repos`)
- Never put business logic in controllers — delegate to services

### Services

- Plain Ruby classes in `app/services/`
- Constructor injection for dependencies (tokens, configs)
- Workflows inherit from `BaseWorkflow` and call `run_agent(prompt:, system_prompt:)`
- Tool builders use `ClaudeAgentSDK.create_tool` and return SDK MCP server hashes

### Tools (RubyLLM::Tool Pattern)

Tool logic lives in `app/tools/` as `RubyLLM::Tool` subclasses. Tool builders in `app/services/` are now lightweight wrappers.

```ruby
# app/tools/github_tools/get_pr_info_tool.rb
module GithubTools
  class GetPRInfoTool < RubyLLM::Tool
    description "Get pull request information"
    param :repo, desc: "Repository full name (owner/name)"
    param :pr_number, desc: "PR number", type: :integer

    def initialize(github_api_service)
      @github = github_api_service
    end

    def execute(repo:, pr_number:)
      @github.get_pr(repo, pr_number)
    rescue => e
      raise ToolError, e.message
    end
  end
end
```

Namespaced tools share a `BaseTool` for common dependencies:

```ruby
# app/tools/github_tools/base_tool.rb
module GithubTools
  class BaseTool < RubyLLM::Tool
    def initialize(github_api_service)
      @github = github_api_service
    end
  end
end
```

Tool builders wrap them for the Claude Agent SDK:

```ruby
# app/services/github_tool_builder.rb — lightweight wrapper
class GithubToolBuilder
  include ToolBuilderSupport

  def build_tools
    [
      wrap_tool(GithubTools::GetPRInfoTool.new(@github)),
      wrap_tool(GithubTools::GetPRDiffTool.new(@github)),
    ]
  end
end
```

Key conventions:
- Use `ToolError` for user-facing error messages (not raw exceptions)
- Organize by namespace: `GithubTools::`, `AutomationTools::`, `SkillTools::`
- `ToolBuilderSupport#wrap_tool` handles SDK format conversion and `deep_symbolize_keys` on params_schema
- Each namespace has a `BaseTool` with shared constructor/dependencies

### Jobs

- Inherit `ApplicationJob`, use `queue_as :default`
- Create tracking records (AgentRun, CodeGeneration) before doing work
- Rescue errors and update status to "failed" with error message
- Broadcast Turbo Streams for real-time UI updates

### Prompts

All prompt text lives in `app/prompts/`. Two file types:

- **`.md`** — static prompts, loaded with `PromptLoader.load("name")`. Cached in production. Use when the prompt has no dynamic content.
- **`.md.erb`** — dynamic prompts, rendered with `PromptLoader.render("name", **locals)`. Not cached. Use when the prompt needs interpolated values (working directory, project context, etc.).
- **`partials/_name.md`** — reusable fragments, loaded with `PromptLoader.partial("name")`. Called from ERB templates.

Rules:
- Never mix: don't call `load` on an `.erb` file or `render` on a plain `.md` file
- If a static prompt gains its first dynamic value, rename `.md` → `.md.erb` and switch callers from `load` to `render`
- Keep prompt logic (conditionals, truncation) in the ERB template, not in Ruby workflow code
- Partials are always static `.md` — if a partial needs interpolation, make it a full ERB template instead

### Prompt Smell — Anti-patterns

When fixing agent behavior, prefer **structural solutions** over **rhetorical solutions**:

- **Don't shout**: `NEVER`, `ALWAYS`, `MANDATORY`, ALL CAPS in prompts means the architecture is wrong. If you need to shout, build a mechanism instead (metadata, routing logic, tool design).
- **Don't hardcode names in shared prompts**: Business-specific skill/feature names in generic templates (like `base_agent.md.erb`) don't scale. Use metadata and dynamic prompt generation — pass data from Ruby, render with ERB conditionals.
- **Don't solve routing with prose**: If the agent should prefer tool A over tool B, that's a routing decision — solve with skill `category` metadata or tool priority, not paragraphs of instructions.
- **Scaling test**: Before adding content to a shared prompt, ask "if we add 5 more of these, does the prompt still work?" If no, the approach is wrong.

## Comments

Ruby is read-aloud. Good code names what it does — comments that duplicate that just add noise. **Default to no comment.** Add one only when the code can't speak for itself.

**Write a comment when**
- **Why, not what**: a non-obvious decision, constraint, gotcha, or external-API quirk the code can't show on its own.
- **Public API contract**: inputs/outputs/side effects on a class or public method another file consumes (esp. `app/services/`, `app/tools/`).
- **Magic constant**: a number/string with hidden semantics (TTL boundary, protocol version, regex intent).
- **`TODO` with a ticket**: `# TODO(LIN-123): ...`. Bare `TODO` rots.

**Do NOT comment when**
- **You're restating the code**: `# Wraps the personal-task RubyLLM tools as SDK tools` above `class TaskToolBuilder` — the name already says it.
- **You're explaining another file's mechanics**: how `ChatToolConfiguration` calls into this, how `MessagingAgentConcern` consumes it — those narratives belong in CLAUDE.md, skill docs, or the commit message. Inline they go stale the first time the caller changes.
- **You're justifying the design**: "Mirrors X so Y can register without bespoke wiring." If the design needs that much defending, refactor it or write a doc.
- **You're annotating a kwarg**: a 5-line preamble explaining what `tasks_enabled:` means → name the parameter clearly and trust the caller to be the proof.
- **You're labeling sections**: `private` already says "private methods". No `# ===== helpers =====` banners.
- **You're stating the obvious**: `# Initialize the user`, `# Loop through results`, `# Return the value`.
- **You're parking dead code**: delete it. Git remembers.

**Style**
- Sentence case, full sentences end with a period.
- Single `#` then one space.
- Keep to ≤2 lines. If you need more, the code or naming is the problem.
- No YARD tags (`@param`, `@return`) — we don't generate docs from them.
- No ASCII banners, no decorative `####` rows.

**The earn-its-place test**
Read the comment, delete it, re-read just the code. Lost information? Keep it. Otherwise it was noise.

## For Detailed Reference

- **Testing with Minitest + Mocha**: See [TESTING.md](TESTING.md)
- **Hotwire / Turbo / Stimulus patterns**: See [HOTWIRE.md](HOTWIRE.md)
