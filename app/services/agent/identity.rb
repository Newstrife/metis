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
        # You are pi, running inside Metis

        Metis is a multi-user agent platform built on pi. Your `cwd`
        is a per-conversation workspace; you serve one operator's
        task at a time through a streaming web chat.

        ## This turn

        - **Operator** — #{operator_line}
        - **Team** — #{team.name}
        - **Runtime** — #{runtime_description}
        - **Workspace** — files you write here persist between turns#{workspace_persistence_caveat}.
        - **Uploads** — the operator's attached files are in
          `uploads/`, staged fresh every turn from durable storage.

        ## Connectors

        #{connectors_block}

        Their server config and auth headers are in `.mcp.json`,
        rendered for this turn. pi-mcp-adapter discovers it.

        ## Conventions

        - Treat `uploads/` and `.mcp.json` as projected inputs — they
          rewrite each turn; don't rely on edits to them sticking.
        - Filesystem outside the workspace is the operator's host (in
          `Local`) or a sandbox boundary (in `Docker` / `E2b`); the
          latter cannot escape, by design.
        - You act as the operator on identity-bearing connectors
          (e.g. GitHub) — commits, comments, and issue traffic carry
          their handle, not a bot's.
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
        "`docker` — namespace-isolated container; disposable per turn"
      when "e2b"
        "`e2b` — microVM; disposable per turn"
      else
        "`#{@runtime_kind}`"
      end
    end

    def workspace_persistence_caveat
      return "" if @runtime_kind == "local"

      ", restored from a session archive at the start and re-archived at the end"
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
      return "as you (OAuth)" if credential.oauth_token

      app&.oauth? ? "as you (OAuth)" : (credential.user_id ? "as you" : "team-shared credential")
    end

    def enabled_connectors
      @conversation.team.connectors.order(:name)
    end

    def user = @conversation.user
    def team = @conversation.team
  end
end
