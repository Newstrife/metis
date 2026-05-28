require "test_helper"

class Agent::RepoSkillsTest < ActiveSupport::TestCase
  test "returns one Listing per repo skill directory with name + description parsed from frontmatter" do
    Dir.mktmpdir do |tmp|
      source = Pathname.new(tmp).join("skills")
      FileUtils.mkdir_p(source.join("alpha"))
      File.write(source.join("alpha/SKILL.md"),
        "---\nname: alpha-readable\ndescription: First skill.\n---\nBody")
      FileUtils.mkdir_p(source.join("beta"))
      File.write(source.join("beta/SKILL.md"), "no frontmatter")

      with_skills_source(source) do
        listings = Agent::RepoSkills.all
        assert_equal %w[alpha beta], listings.map(&:slug)
        alpha = listings.find { |l| l.slug == "alpha" }
        assert_equal "alpha-readable", alpha.name
        assert_equal "First skill.", alpha.description
        beta = listings.find { |l| l.slug == "beta" }
        assert_equal "beta", beta.name # falls back to slug
        assert_nil beta.description
      end
    end
  end

  test "skips directories without SKILL.md and non-directory entries" do
    Dir.mktmpdir do |tmp|
      source = Pathname.new(tmp).join("skills")
      FileUtils.mkdir_p(source.join("missing"))   # no SKILL.md
      File.write(source.join("loose.md"), "not a dir")
      FileUtils.mkdir_p(source.join("ok"))
      File.write(source.join("ok/SKILL.md"), "---\nname: ok\n---\nBody")

      with_skills_source(source) do
        assert_equal [ "ok" ], Agent::RepoSkills.all.map(&:slug)
      end
    end
  end

  test "returns empty when SKILLS_SOURCE is absent" do
    Dir.mktmpdir do |tmp|
      with_skills_source(Pathname.new(tmp).join("absent")) do
        assert_empty Agent::RepoSkills.all
      end
    end
  end

  private

  def with_skills_source(path)
    original = Agent::Workspace::SKILLS_SOURCE
    Agent::Workspace.send(:remove_const, :SKILLS_SOURCE)
    Agent::Workspace.const_set(:SKILLS_SOURCE, path)
    yield
  ensure
    Agent::Workspace.send(:remove_const, :SKILLS_SOURCE)
    Agent::Workspace.const_set(:SKILLS_SOURCE, original)
  end
end
