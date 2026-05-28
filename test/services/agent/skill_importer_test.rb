require "test_helper"

class Agent::SkillImporterTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "import@example.com", password: "password123")
    @team = @user.personal_team
    # Decouple from whatever the host has at .pi/skills/ so slug collisions
    # don't depend on the developer's local checkout.
    Agent::Workspace.singleton_class.alias_method(:_orig_repo_slugs, :repo_slugs)
    Agent::Workspace.define_singleton_method(:repo_slugs) { Set.new }
  end

  teardown do
    Agent::Workspace.define_singleton_method(:repo_slugs,
      Agent::Workspace.singleton_class.instance_method(:_orig_repo_slugs))
  end

  test "parses owner/repo shorthand and imports a single-file skill" do
    with_github_routes(
      "https://api.github.com/repos/acme/cool-skill/contents/" =>
        [ file_entry("SKILL.md", "https://raw/SKILL.md") ],
      "https://raw/SKILL.md" => "---\nname: cool\ndescription: Be cool.\n---\n# Cool\n"
    ) do
      skill = Agent::SkillImporter.from_github(url: "acme/cool-skill", team: @team, by: @user)
      assert_equal "cool-skill", skill.slug
      assert_equal "Be cool.", skill.description
      assert_includes skill.file_list, "SKILL.md"
    end
  end

  test "parses a tree URL with a nested path and uses the leaf as slug" do
    with_github_routes(
      "https://api.github.com/repos/acme/skills/contents/docs/pdf?ref=main" =>
        [ file_entry("docs/pdf/SKILL.md", "https://raw/SKILL.md"),
          file_entry("docs/pdf/notes.md", "https://raw/notes.md") ],
      "https://raw/SKILL.md" => "---\nname: pdf\ndescription: PDF stuff.\n---\nBody",
      "https://raw/notes.md" => "notes content"
    ) do
      skill = Agent::SkillImporter.from_github(
        url: "https://github.com/acme/skills/tree/main/docs/pdf",
        team: @team, by: @user
      )
      assert_equal "pdf", skill.slug
      assert_equal [ "SKILL.md", "notes.md" ].sort, skill.file_list
    end
  end

  test "walks nested directories" do
    with_github_routes(
      "https://api.github.com/repos/acme/skills/contents/foo" =>
        [ file_entry("foo/SKILL.md", "https://raw/SKILL.md"),
          dir_entry("foo/refs") ],
      "https://api.github.com/repos/acme/skills/contents/foo/refs" =>
        [ file_entry("foo/refs/style.md", "https://raw/style.md") ],
      "https://raw/SKILL.md" => "---\nname: foo\n---\nBody",
      "https://raw/style.md" => "style"
    ) do
      skill = Agent::SkillImporter.from_github(url: "acme/skills/foo", team: @team, by: @user)
      assert_equal [ "SKILL.md", "refs/style.md" ].sort, skill.file_list
    end
  end

  test "raises when SKILL.md is missing" do
    with_github_routes(
      "https://api.github.com/repos/acme/no-skill/contents/" =>
        [ file_entry("README.md", "https://raw/README.md") ],
      "https://raw/README.md" => "not a skill"
    ) do
      assert_raises(Agent::SkillImporter::Error) do
        Agent::SkillImporter.from_github(url: "acme/no-skill", team: @team, by: @user)
      end
    end
  end

  test "rejects unparseable URLs" do
    assert_raises(Agent::SkillImporter::Error) do
      Agent::SkillImporter.from_github(url: "not-a-repo", team: @team, by: @user)
    end
  end

  test "accepts the skills.sh `owner/repo@name` shorthand" do
    with_github_routes(
      "https://api.github.com/repos/awslabs/agent-plugins/contents/skills/aws-architecture-diagram" =>
        [ file_entry("skills/aws-architecture-diagram/SKILL.md", "https://raw/SKILL.md") ],
      "https://raw/SKILL.md" => "---\nname: aws-architecture-diagram\n---\nBody"
    ) do
      skill = Agent::SkillImporter.from_github(
        url: "awslabs/agent-plugins@aws-architecture-diagram",
        team: @team, by: @user
      )
      assert_equal "aws-architecture-diagram", skill.slug
    end
  end

  test "strips trailing SKILL.md from a blob URL" do
    with_github_routes(
      "https://api.github.com/repos/acme/skills/contents/foo?ref=main" =>
        [ file_entry("foo/SKILL.md", "https://raw/SKILL.md") ],
      "https://raw/SKILL.md" => "---\nname: foo\n---\nBody"
    ) do
      skill = Agent::SkillImporter.from_github(
        url: "https://github.com/acme/skills/blob/main/foo/SKILL.md",
        team: @team, by: @user
      )
      assert_equal "foo", skill.slug
    end
  end

  private

  def file_entry(path, download_url)
    { "type" => "file", "path" => path, "download_url" => download_url, "size" => 100 }
  end

  def dir_entry(path)
    { "type" => "dir", "path" => path }
  end

  # Override Net::HTTP#request for the block. Maps URL -> body string
  # or Ruby object (JSON-encoded). Raises on unstubbed URLs to make
  # missing routes visible immediately.
  def with_github_routes(routes)
    original = Net::HTTP.instance_method(:request)
    Net::HTTP.define_method(:request) do |req|
      query = req.path.dup
      url = "#{use_ssl? ? "https" : "http"}://#{address}#{query}"
      payload = routes[url]
      raise "unstubbed GitHub URL: #{url}" if payload.nil?

      body = payload.is_a?(String) ? payload : payload.to_json
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@body, body)
      response.instance_variable_set(:@read, true)
      response
    end
    yield
  ensure
    Net::HTTP.define_method(:request, original)
  end
end
