require "fileutils"

module Agent
  # Resolves the durable on-disk location for a conversation's agent
  # files. Today that means pi's session directory; a per-conversation
  # working directory will live here too.
  #
  # pi session files are the agent's conversation memory — losing them
  # breaks `--continue`. They therefore live under a persistent,
  # configurable root (config.x.agent.root), never under tmp/.
  #
  # Paths are scoped per user; a tenant segment slots into #scope when
  # multi-tenancy lands. This is the single place path layout is
  # decided.
  #
  # Constraint: this is local-disk storage. It assumes the job worker
  # that runs a conversation can see the same filesystem across that
  # conversation's lifetime — true for a single-server deployment or a
  # shared filesystem. Multi-worker deployments without shared storage
  # will need session content backed by the DB or an object store and
  # materialized here around each run; this class is the seam for that.
  class Workspace
    def self.for(conversation)
      new(conversation)
    end

    def initialize(conversation)
      @conversation = conversation
    end

    # Directory passed to `pi --session-dir`. Pure path — call #prepare!
    # to make sure it exists on disk.
    def session_dir
      scope.join("sessions")
    end

    def prepare!
      FileUtils.mkdir_p(session_dir)
      self
    end

    private

    def scope
      # A tenant segment (e.g. "t#{tenant_id}") slots in here later.
      root.join("u#{@conversation.user_id}", "c#{@conversation.id}")
    end

    def root
      Rails.application.config.x.agent.root
    end
  end
end
