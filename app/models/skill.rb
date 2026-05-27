# A team-authored skill — one directory pi sees under
# workspace/.pi/skills/<slug>/, projected per turn by
# Agent::Workspace#stage_skills. SKILL.md (with frontmatter
# name+description) plus any supporting files; the agent
# auto-discovers it from cwd. See docs/skills.md.
class Skill < ApplicationRecord
  SKILL_MD = "SKILL.md"
  SLUG_FORMAT = /\A[a-z0-9][a-z0-9\-]*\z/
  EXAMPLE_MAX_LENGTH = 200
  MAX_EXAMPLES = 10

  # Starter SKILL.md for the new-skill form. pi reads `name` and
  # `description` from the YAML frontmatter to decide auto-trigger;
  # the body is the instructions it loads on a match.
  DEFAULT_SKILL_MD = <<~MD
    ---
    name: my-skill
    description: When the agent should reach for this — one line.
    ---

    # My skill

    Walk the agent through what to do, step by step. Keep it short.
  MD

  TEXT_CONTENT_TYPES = %w[
    text/plain text/markdown text/html text/css text/javascript text/xml text/csv
    application/json application/xml application/x-yaml
  ].freeze

  TEXT_EXTENSIONS = Set.new(%w[
    .md .txt .py .rb .js .ts .json .yml .yaml .html .css .csv .xml .sh .sql
    .erb .jinja .j2 .toml .cfg .ini
  ]).freeze

  belongs_to :team
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  has_many_attached :files

  validates :slug, presence: true,
                    uniqueness: { scope: :team_id },
                    format: { with: SLUG_FORMAT,
                              message: "only lowercase letters, numbers, and hyphens" }
  validate :slug_not_in_repo_tree
  validate :validate_examples

  before_validation :normalize_examples

  scope :enabled, -> { where(enabled: true) }

  def self.text_extension?(path)
    TEXT_EXTENSIONS.include?(File.extname(path).downcase)
  end

  # Pull a `description:` value out of SKILL.md YAML frontmatter.
  # Conservative single-pass parser: avoids depending on YAML/Psych
  # for a two-field shape, and tolerates the absence of frontmatter
  # entirely. Returns nil when absent.
  def self.parse_description(content)
    return nil unless content.is_a?(String) && content.start_with?("---")

    match = content.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    return nil unless match

    match[1].each_line do |line|
      next unless (m = line.match(/\Adescription:\s*(.*)/))

      return m[1].strip.gsub(/\A["']|["']\z/, "")
    end
    nil
  end

  # Body of SKILL.md — denormalized to content_cache for fast list
  # rendering, falls back to the blob on a cache miss.
  def skill_md_content
    return content_cache if content_cache.present?

    skill_md = files.find { |f| relative_path(f) == SKILL_MD }
    skill_md&.download&.force_encoding("UTF-8")
  end

  # Replace SKILL.md and mirror to content_cache in one write. Caller
  # is responsible for save!.
  def replace_skill_md!(content)
    replace_file!(SKILL_MD, content, "text/markdown")
    self.content_cache = content
  end

  # Replace (or attach) any file by relative path. Blob metadata keeps
  # the path so the same skill can back a tree, not just one file.
  def replace_file!(relative_path, content, content_type = nil)
    raise ArgumentError, "Invalid relative path" if relative_path.include?("..")

    existing = files.find { |f| f.blob.metadata["relative_path"] == relative_path }
    existing&.purge

    content_type ||= Marcel::MimeType.for(name: relative_path)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content),
      filename: File.basename(relative_path),
      content_type: content_type,
      metadata: { "relative_path" => relative_path }
    )
    files.attach(blob)
  end

  # Write every attached file into `dir`, preserving the relative tree.
  # Path traversal is rejected; absolute/`..` segments are skipped.
  def extract_to(dir)
    files.each do |file|
      rel = Pathname.new(relative_path(file)).cleanpath.to_s
      next if rel.start_with?("..") || rel.start_with?("/")

      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, file.download)
    end
  end

  # Rebuild content_cache from the attached SKILL.md. tracked:true
  # uses update! (for user actions); tracked:false uses update_column
  # (for system jobs that shouldn't touch updated_at).
  def refresh_content_cache!(tracked: false)
    files.reload
    new_content = files.find { |f| relative_path(f) == SKILL_MD }&.download&.force_encoding("UTF-8")
    return if content_cache == new_content

    if tracked
      update!(content_cache: new_content)
    else
      update_column(:content_cache, new_content)
    end
  end

  def file_list
    files.map { |f| relative_path(f) }.sort
  end

  def relative_path(file)
    file.blob.metadata["relative_path"] || file.filename.to_s
  end

  def text_file?(file)
    TEXT_CONTENT_TYPES.include?(file.content_type) || self.class.text_extension?(file.filename.to_s)
  end

  def editable_file?(file)
    text_file?(file) && relative_path(file) != SKILL_MD
  end

  # Normalized examples array (always non-empty strings). Frontmatter
  # / form input may produce blanks; this is the canonical accessor.
  def example_strings
    Array(examples).filter_map { |e| e.to_s.strip.presence }
  end

  private

  # Repo skills and team skills share workspace/.pi/skills/ at runtime;
  # the two trees are merged. A team can never claim a slug the repo
  # already ships — the projection would override the repo copy and the
  # provenance question becomes ambiguous. The ingest path also filters
  # by repo slug (see Workspace#ingest_team_skills) as a runtime guard.
  def slug_not_in_repo_tree
    return if slug.blank?
    return unless Agent::Workspace.repo_slugs.include?(slug)

    errors.add(:slug, "is reserved by a built-in repo skill")
  end

  def normalize_examples
    self.examples = Array(examples).filter_map { |raw| raw.to_s.strip.presence }
  end

  def validate_examples
    list = Array(examples)
    errors.add(:examples, "can have at most #{MAX_EXAMPLES} entries") if list.size > MAX_EXAMPLES

    list.each_with_index do |raw, i|
      next unless raw.is_a?(String) || raw.respond_to?(:to_s)
      if raw.to_s.length > EXAMPLE_MAX_LENGTH
        errors.add(:examples, "entry ##{i + 1} is longer than #{EXAMPLE_MAX_LENGTH} characters")
      end
    end
  end
end
