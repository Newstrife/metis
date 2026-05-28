module Agent
  # Read-only view of the repo's .pi/skills/ tree, parsed for slug,
  # name, and description. Surfaced under the "Built-in" tab on
  # /settings/skills so operators can see which system skills are
  # active without having to grep the repo.
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
        name: parse_field(body, "name") || path.basename.to_s,
        description: parse_field(body, "description")
      )
    end

    def parse_field(body, field)
      return nil unless body.start_with?("---")
      match = body.match(/\A---\s*\n(.*?)\n---\s*\n/m)
      return nil unless match

      match[1].each_line do |line|
        if (m = line.match(/\A#{Regexp.escape(field)}:\s*(.*)/))
          return m[1].strip.gsub(/\A["']|["']\z/, "")
        end
      end
      nil
    end
  end
end
