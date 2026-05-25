require "fileutils"

module Agent
  # Resolves the on-disk scope for a conversation's agent run, and stages
  # uploads into it.
  #
  # A scope holds:
  #   sessions/           pi's --session-dir (the transcript)
  #   workspace/          pi's working directory
  #   workspace/uploads/  staged user uploads — projected each turn from
  #                       the durable Message attachments, never archived
  #                       (see docs/session-persistence.md)
  #   workspace/.mcp.json MCP connector config — rendered each turn from
  #                       the conversation's Connectors, never archived
  #   workspace/AGENTS.md Agent boot identity — rendered each turn (see
  #                       Agent::Identity), never archived, pi auto-loads
  #   workspace/.pi/skills/  Project skills — projected each turn from
  #                          the repo's .pi/skills/ tree (see
  #                          stage_skills), never archived, pi auto-discovers
  #
  # Two roots, because persistence is a per-runtime concern:
  #   Workspace.scratch    — under tmp/, for a runtime that re-hydrates
  #                          the scope from the archive each turn (Docker)
  #   Workspace.persistent — under storage/, for Runtime::Local, which
  #                          keeps the scope between turns and relies on
  #                          pi's own file-based session management
  class Workspace
    SCRATCH_ROOT = Rails.root.join("tmp/agent").freeze
    PERSISTENT_ROOT = Rails.root.join("storage/agent").freeze
    SKILLS_SOURCE = Rails.root.join(".pi/skills").freeze
    SKILLS_SUBPATH = ".pi/skills".freeze

    def self.scratch(conversation)
      new(conversation, SCRATCH_ROOT)
    end

    def self.persistent(conversation)
      new(conversation, PERSISTENT_ROOT)
    end

    def initialize(conversation, root)
      @conversation = conversation
      @root = root
    end

    # The conversation's whole scope.
    def scope_dir
      @root.join("u#{@conversation.user_id}", "c#{@conversation.id}")
    end

    def session_dir = scope_dir.join("sessions")
    def workspace_dir = scope_dir.join("workspace")
    def uploads_dir = workspace_dir.join("uploads")

    # Discard any stale scope and recreate it empty — for a runtime that
    # repopulates it from the archive.
    def reset!
      FileUtils.rm_rf(scope_dir)
      ensure!
    end

    # Create the scope directories if absent, leaving existing content.
    def ensure!
      [ session_dir, workspace_dir, uploads_dir ].each { |dir| FileUtils.mkdir_p(dir) }
      self
    end

    # Project uploaded file attachments into uploads/. Filenames are
    # basenamed so a crafted name cannot escape the workspace.
    def stage_uploads(attachments)
      FileUtils.mkdir_p(uploads_dir)
      attachments.each do |attachment|
        name = File.basename(attachment.filename.to_s)
        next if name.blank? || [ ".", ".." ].include?(name)

        attachment.open { |io| IO.copy_stream(io, uploads_dir.join(name)) }
      end
    end

    # Write the rendered .mcp.json into the workspace root — a per-turn
    # projected input like uploads/, overwritten each turn and never
    # archived (see docs/connectors.md).
    def stage_mcp_config(content)
      File.write(workspace_dir.join(McpConfig::FILENAME), content)
    end

    # Write the rendered AGENTS.md into the workspace root. pi auto-loads
    # it from `cwd` as ambient instructions — the agent boots reading
    # this every turn. Per-turn projected input like .mcp.json: rendered
    # fresh each turn, never archived. See Agent::Identity.
    def stage_identity(content)
      File.write(workspace_dir.join(Identity::FILENAME), content)
    end

    # Project the repo's .pi/skills/ tree into workspace/.pi/skills/.
    # pi auto-discovers skills there relative to cwd. Per-turn projected
    # input — the repo is the canonical source; the destination is
    # cleared first so a deleted skill disappears from the workspace.
    # No-op when the source dir is absent.
    def stage_skills
      return unless SKILLS_SOURCE.directory?

      dest = workspace_dir.join(SKILLS_SUBPATH)
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.cp_r(SKILLS_SOURCE, dest)
    end
  end
end
