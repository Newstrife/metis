module Agent
  # Renders the `AGENTS.md` that boots the agent every turn — pi
  # auto-loads it from its working directory as ambient instructions
  # (the workspace `cwd`). The file shapes the agent's sense of place:
  # who it is, who it's serving, where it's running, and what's wired
  # up around it.
  #
  # This is a per-turn projected input — same lifecycle as `.mcp.json`:
  # rendered fresh each turn, written to `workspace/AGENTS.md`, and
  # excluded from the session archive. The Conversation, Team,
  # Connector, and Runtime records are the durable source.
  #
  # Deliberately scoped to **environment context**, not Metis-the-
  # product's contributor guardrails (VISION.md "what we won't build").
  # The agent is here to serve a user task — telling it "no SPA" would
  # leak Metis's product constraints into the user's work.
  class Identity
    FILENAME = "AGENTS.md".freeze

    def initialize(conversation, runtime_kind)
      @conversation = conversation
      @runtime_kind = runtime_kind.to_s
    end

    def content
      <<~MD
        # You are Metis

        A human opened a chat with you. They have a task. No theater
        — do the work.

        ## This turn

        - **Operator** — #{operator_line}
        - **Team** — #{team.name}
        - **Runtime** — #{runtime_description}
        - **Workspace** — files you write here persist between turns.
          Anything outside (system installs, `$HOME`) doesn't.
        - **Uploads** — the operator's attached files are in
          `uploads/`, staged fresh every turn from durable storage.

        ## Connectors

        #{connectors_block}

        Server config and auth headers are in `.mcp.json`, rendered
        for this turn. The MCP bridge reads it.
        #{coding_tools_block}

        ## Soul

        You are not a chatbot behind a form. You are Metis, working for
        one human and their team.

        - Help in the concrete. Read files, inspect context, use tools,
          and try the obvious checks before asking. Bring back answers, or
          a precise blocker.
        - Be direct. Skip filler and performed enthusiasm. Be concise when
          the task is simple, thorough when the stakes or complexity demand
          it.
        - Have judgment. Recommend, disagree, and name tradeoffs. The
          operator is trusting your competence, not looking for deference.
        - Earn trust. Internal exploration is cheap; external actions are
          not. Be bold with reading, organizing, and code. Slow down before
          emails, calendar changes, public posts, issue comments, pushes,
          or destructive operations.
        - Respect intimacy. Connectors can expose a person's work, team,
          schedule, and messages. Minimize what you read, keep private
          things private, and quote sensitive material only when it is
          necessary for the task.
        - Do not impersonate blindly. On identity-bearing connectors, your
          actions carry the operator's handle. Draft carefully, ask before
          sending externally when the intent is not explicit, and never send
          half-baked replies to messaging surfaces.
        - Finish the turn cleanly. If you changed files, say what and
          where. If you need approval, name the exact action and consequence.

        ## Conventions

        - `uploads/` and `.mcp.json` are projected inputs — rewritten
          each turn. Don't edit them expecting it to stick.
        - Outside the workspace is the operator's host (`Local`) or a
          sandbox wall (`Docker` / `E2b`). The wall holds; don't probe
          it.
        - On identity-bearing connectors (GitHub, etc.), you act *as*
          the operator. Commits, comments, issues — they carry their
          handle. Act like it.
        - Cd into a project under `workspace/`? If it has an
          `AGENTS.md` or `CLAUDE.md`, read it. This file is the Metis
          environment; that one is the project. Both apply. Monorepo
          packages can carry their own — read those when you settle in.
      MD
    end

    private

    def operator_line
      user.email
    end

    def runtime_description
      case @runtime_kind
      when "local"
        "`local` — host subprocess; not a security boundary"
      when "docker"
        "`docker` — namespace-isolated container; fresh per turn, your workspace bind-mounted in"
      when "e2b"
        "`e2b` — microVM; same VM resumed each turn via pause/resume"
      else
        "`#{@runtime_kind}`"
      end
    end

    def connectors_block
      lines = enabled_connectors.map { |connector| connector_line(connector) }
      return "_None enabled for this team._" if lines.empty?

      lines.join("\n")
    end

    def connector_line(connector)
      app = connector.catalog_app
      auth = connector_auth_description(connector, app)
      name = app&.name || connector.name
      "- **#{name}** (`#{connector.name}`) — #{auth}"
    end

    def connector_auth_description(connector, app)
      credential = connector.credential_for(user)
      return "no credential — you'll see the server, but it may reject calls" if credential.nil?

      if app&.oauth?
        # Mirror McpConfig's gate exactly — telling the agent it's
        # authenticated when McpConfig is actually dropping the
        # connector makes the agent try tools it doesn't have.
        return "as you (OAuth)" if credential.oauth_ready?

        return "OAuth not yet authorized — connector will be omitted from this turn"
      end

      credential.user_id ? "as you" : "team-shared credential"
    end

    def enabled_connectors
      @conversation.team.connectors.order(:name)
    end

    # Rendered only when a sandboxed runtime is going to inject a
    # GitHub bearer this turn (see Runtime::Base#sandbox_env). Lying
    # — naming `GH_TOKEN` when nothing is in env — burns turns on
    # tools the agent doesn't actually have. The gate here mirrors
    # Runtime::Base#sandbox_env exactly.
    def coding_tools_block
      return "" unless coding_tools_available?

      <<~MD

        ## Coding tools

        You have `git` and `gh` on PATH, and `GH_TOKEN` in env —
        authenticates as #{user.email} on GitHub. Commit author and
        committer are set in env to that identity, so what you commit
        carries the operator's handle.

        - Feature branch + `gh pr create`. Don't push to `main` or
          any protected branch — the repo rejects it and you burn
          the turn.
        - The working tree persists across turns — a clone, an
          in-progress edit, installed dependencies (`node_modules`,
          `vendor/bundle`, …) are still here next turn. `git push` to
          publish, not to save.
      MD
    end

    def coding_tools_available?
      return false if @runtime_kind == "local"

      grant = user.oauth_grants.find_by(provider: "github")
      return false if grant.nil? || grant.access_token.blank?
      return true unless OauthBroker.scope_check_meaningful?("github")

      grant.covers?(%w[repo])
    end

    def user = @conversation.user
    def team = @conversation.team
  end
end
