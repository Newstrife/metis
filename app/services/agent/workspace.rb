require "fileutils"

module Agent
  # Resolves the on-disk scope for a conversation's agent run, and stages
  # uploads into it.
  #
  # A scope holds:
  #   sessions/             pi's --session-dir (the transcript)
  #   workspace/            pi's working directory
  #   workspace/uploads/    staged user uploads — projected each turn from
  #                         the durable Message attachments, never archived
  #                         (see docs/session-persistence.md)
  #   workspace/.mcp.json   MCP connector config — rendered each turn from
  #                         the conversation's Connectors, never archived
  #   workspace/AGENTS.md   Agent boot identity — rendered each turn (see
  #                         Agent::Identity), never archived, pi auto-loads
  #   workspace/.pi/skills/ Skills pi auto-discovers — staged each turn
  #                         from the repo's .pi/skills/ tree plus the
  #                         team's enabled Skill rows. Never archived;
  #                         the tree is wiped & rewritten on every turn
  #                         so agent edits don't accumulate (see
  #                         stage_skills + ingest_team_skills, and
  #                         docs/skills.md).
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
    # Created lazily by the agent — Metis never provisions it.
    ARTIFACTS_SUBPATH = "artifacts".freeze

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
    def artifacts_dir = workspace_dir.join(ARTIFACTS_SUBPATH)
    def skills_dir = workspace_dir.join(SKILLS_SUBPATH)

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

    # Project skills into workspace/.pi/skills/ where pi auto-discovers
    # them. Two sources, layered into one tree:
    #
    #   1. Repo skills from SKILLS_SOURCE (versioned in git, identical
    #      for every team)
    #   2. Team skills from the conversation's team.skills.enabled
    #      (DB-authored, per-team)
    #
    # The dest is wiped first so a deleted skill (in either source)
    # disappears next turn — and so any agent writes from the prior
    # turn are erased before pi sees the tree. That last property is
    # load-bearing: the agent CAN modify any subdir during a turn,
    # but the repo copy is restored fresh before the next turn, so
    # tampering cannot accumulate.
    #
    # Slug collisions between repo and team are prevented at save time
    # by Skill#slug_not_in_repo_tree. The ingest path also filters by
    # repo slug as a runtime guard (see ingest_team_skills).
    def stage_skills
      dest = skills_dir
      FileUtils.rm_rf(dest)

      if SKILLS_SOURCE.directory?
        FileUtils.mkdir_p(dest.dirname)
        FileUtils.cp_r(SKILLS_SOURCE, dest)
      end

      team_skills = @conversation.team.skills.enabled
      return if team_skills.empty?

      FileUtils.mkdir_p(dest)
      team_skills.find_each { |skill| skill.extract_to(dest.join(skill.slug)) }
    end

    # Sync agent-written skills back to the team. The adapter (see
    # Agent::Adapters::Pi#note_skill_touched) collects the slug set
    # from pi's write/edit/bash tool events as they stream — so by
    # the time we're called, `slugs` is exactly the set of dirs to
    # ingest. No tree scan, no mtime gate. Repo slugs are filtered
    # (the repo is read-only — see Workspace.repo_slugs).
    #
    # Upsert only — a slug not present here does NOT delete its row.
    # The operator's UI keeps that responsibility. See docs/skills.md.
    def ingest_team_skills(slugs:, by:)
      return if slugs.empty?
      return unless skills_dir.directory?

      repo_slugs = self.class.repo_slugs
      slugs.each do |slug|
        next if repo_slugs.include?(slug)
        next unless Skill::SLUG_FORMAT.match?(slug)

        ingest_one_skill_from_disk(skills_dir.join(slug), by: by)
      end
    end

    # DB-side of ingest, independent of where the files came from.
    # Host runtimes (Local/Docker) build the `files` map from disk;
    # E2b builds it by reading from the sandbox. Both call this.
    # `files`: Hash of relative path -> bytes. Must include "SKILL.md".
    def ingest_team_skill_from_files(slug:, files:, by:)
      return unless Skill::SLUG_FORMAT.match?(slug)
      return if self.class.repo_slugs.include?(slug)

      body = files[Skill::SKILL_MD]
      return if body.blank?

      body = body.dup.force_encoding("UTF-8")
      skill = @conversation.team.skills.find_or_initialize_by(slug: slug)
      skill.created_by ||= by
      skill.updated_by = by
      if (desc = Skill.parse_description(body)).present?
        skill.description = desc
      end
      skill.content_cache = body

      # The slug is here because the adapter saw pi write/edit/bash a
      # path under it this turn — explicit intent. Re-attach the whole
      # file map even when SKILL.md happens to be unchanged, because
      # a supporting file may have changed. Per-file diffing would be
      # cheaper but adds enough complexity that it's not worth the
      # rare "agent wrote identical bytes" case.
      skill.files.purge if skill.persisted?
      skill.save!

      files.each do |rel, content|
        skill.replace_file!(rel, content)
      end
    rescue StandardError => e
      Rails.logger.warn("ingest_team_skill(slug=#{slug}) failed for conversation #{@conversation.id}: #{e.message}")
    end

    # Set of slugs the repo currently ships at .pi/skills/. Used to
    # filter ingest (above) and the Skill model's uniqueness
    # validation, so team skills can never shadow a repo skill.
    def self.repo_slugs
      return Set.new unless SKILLS_SOURCE.directory?

      SKILLS_SOURCE.children
        .select(&:directory?)
        .map { |p| p.basename.to_s }
        .to_set
    end

    private

    def ingest_one_skill_from_disk(skill_dir, by:)
      return unless skill_dir.directory?

      files = skill_dir.glob("**/*").reject(&:directory?).each_with_object({}) do |path, h|
        rel = path.relative_path_from(skill_dir).to_s
        h[rel] = path.binread
      end
      return if files.empty?

      ingest_team_skill_from_files(slug: skill_dir.basename.to_s, files: files, by: by)
    end
  end
end
