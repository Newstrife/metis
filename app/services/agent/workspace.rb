require "fileutils"

module Agent
  # Resolves the local scratch directories for a conversation's agent run.
  #
  # A conversation's scope contains two directories:
  #   sessions/   — pi's --session-dir (the agent's transcript)
  #   workspace/  — pi's working directory (where its bash/edit operate)
  #
  # This is disposable working space. The durable, worker-independent
  # copy of the whole scope lives in Active Storage (Agent::SessionArchive),
  # restored here before a run and captured back after. Because it is pure
  # scratch, it correctly lives under tmp/.
  #
  # Paths are scoped per user; a tenant segment slots into #scope_dir when
  # multi-tenancy lands. This is the single place path layout is decided.
  class Workspace
    ROOT = Rails.root.join("tmp/agent").freeze

    def self.for(conversation)
      new(conversation)
    end

    def initialize(conversation)
      @conversation = conversation
    end

    # The conversation's whole scratch scope — this is what gets archived.
    def scope_dir
      # A tenant segment (e.g. "t#{tenant_id}") slots in here later.
      ROOT.join("u#{@conversation.user_id}", "c#{@conversation.id}")
    end

    # Directory passed to `pi --session-dir`.
    def session_dir
      scope_dir.join("sessions")
    end

    # Directory pi runs in — its bash/edit/write operate relative to here.
    def workspace_dir
      scope_dir.join("workspace")
    end

    # Discard any stale scratch from a previous run and recreate the empty
    # scope, ready to be repopulated from the archive.
    def prepare!
      FileUtils.rm_rf(scope_dir)
      FileUtils.mkdir_p(session_dir)
      FileUtils.mkdir_p(workspace_dir)
      self
    end
  end
end
