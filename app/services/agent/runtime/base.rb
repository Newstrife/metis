module Agent
  module Runtime
    # Interface every runtime implements. A runtime decides where the
    # agent process physically runs and how its filesystem persists.
    class Base
      attr_reader :conversation

      def initialize(conversation:)
        @conversation = conversation
      end

      # Directory the agent should pass to `pi --session-dir`.
      def session_dir
        raise NotImplementedError, "#{self.class} must implement #session_dir"
      end

      # Paths to the app's pi extensions (Agent::Runtime.extension_sources)
      # as reachable from this runtime's execution environment, for the Pi
      # adapter to load with `pi --extension`. A runtime that runs pi where
      # the repo files are absent must make them reachable and return those
      # paths. Default: none.
      def extension_paths
        []
      end

      # The rendered `.mcp.json` (Agent::McpConfig) for this
      # conversation's connectors, for a runtime to stage into pi's
      # workspace each turn.
      def mcp_config
        Agent::McpConfig.new(conversation).content
      end

      # The rendered AGENTS.md (Agent::Identity) — the agent boot file
      # pi auto-loads from its working directory each turn. Per-turn
      # projected input, like mcp_config.
      def identity_content
        Agent::Identity.new(conversation, kind).content
      end

      # The runtime's short name (`local`, `docker`, `e2b`) — used in
      # the agent identity file and the runtime_info trace.
      def kind
        self.class.name.demodulize.underscore
      end

      # Provision the runtime, open a PiAgent::Session running pi with
      # `pi_args`, yield it to the caller, then finalize (persist state,
      # tear down). The session is closed by the runtime, not the caller.
      #
      # The runtime also projects the conversation's uploaded files
      # (Conversation#uploaded_files) into pi's workspace/uploads/ — a
      # filesystem operation each runtime does its own way.
      def run(pi_args:)
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      # A record of where the turn ran, persisted on the Conversation:
      # the runtime name, plus whatever per-run detail a subclass adds.
      def runtime_info
        { "runtime" => kind }
      end

      # Per-turn process environment to expose to the agent inside the
      # sandbox — credentials projected from the operator's OauthGrants.
      # Each entry is conditional on the operator having authorised the
      # underlying grant; nothing here is stored and nothing reaches disk.
      # See docs/connectors.md ("Credential pass-through to the sandbox").
      #
      # Today: GitHub. The agent gets `GH_TOKEN` (consumed by `git` and
      # `gh`) plus a git author/committer identity so commits carry the
      # operator's handle rather than an anonymous default.
      def sandbox_env
        env = {}
        github = OauthBroker.bearer_for(
          user: conversation.user, provider: "github", required_scopes: %w[repo]
        )
        if github
          env["GH_TOKEN"] = github
          author = git_identity_for(conversation.user)
          env["GIT_AUTHOR_NAME"]     = author[:name]
          env["GIT_AUTHOR_EMAIL"]    = author[:email]
          env["GIT_COMMITTER_NAME"]  = author[:name]
          env["GIT_COMMITTER_EMAIL"] = author[:email]
        end
        env
      end

      private

      def git_identity_for(user)
        email = user.email.to_s
        local = email.split("@", 2).first.presence || "metis-user"
        { name: local, email: email }
      end
    end
  end
end
