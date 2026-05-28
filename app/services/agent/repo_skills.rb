module Agent
  # Read-only view of the repo's .pi/skills/ tree for the Built-in tab.
  module RepoSkills
    Listing = Struct.new(:slug, :name, :description, keyword_init: true)

    module_function

    def all
      source = Agent::Workspace::SKILLS_SOURCE
      return [] unless source.directory?

      source.children.filter_map { |path| listing_for(path) }.sort_by(&:slug)
    end

    def listing_for(path)
      return nil unless path.directory?
      skill_md = path.join(Skill::SKILL_MD)
      return nil unless skill_md.file?

      body = skill_md.read
      Listing.new(
        slug: path.basename.to_s,
        name: Skill.parse_field(body, "name") || path.basename.to_s,
        description: Skill.parse_field(body, "description")
      )
    end
  end
end
