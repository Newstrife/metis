require "fileutils"

module Agent
  # Resolves the local scratch directory for a conversation's pi run.
  #
  # This is disposable working space — pi reads and writes session files
  # here during a run. The durable, worker-independent copy of the
  # session lives in Active Storage (see Agent::SessionArchive), which is
  # restored into this directory before a run and captured back after.
  # Because it is pure scratch, it correctly lives under tmp/.
  #
  # Paths are scoped per user; a tenant segment slots into #scope when
  # multi-tenancy lands. This is the single place path layout is decided.
  class Workspace
    ROOT = Rails.root.join("tmp/agent").freeze

    def self.for(conversation)
      new(conversation)
    end

    def initialize(conversation)
      @conversation = conversation
    end

    # Directory passed to `pi --session-dir`. Pure path — call #prepare!
    # to materialize a clean copy on disk.
    def session_dir
      scope.join("sessions")
    end

    # Create an empty session directory, discarding any stale scratch
    # from a previous run so it can be repopulated from the archive.
    def prepare!
      FileUtils.rm_rf(session_dir)
      FileUtils.mkdir_p(session_dir)
      self
    end

    private

    def scope
      # A tenant segment (e.g. "t#{tenant_id}") slots in here later.
      ROOT.join("u#{@conversation.user_id}", "c#{@conversation.id}")
    end
  end
end
