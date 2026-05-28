require "net/http"
require "json"
require "uri"

module Agent
  # Import a team skill from a public GitHub directory. Accepts the
  # shorthand `owner/repo[/path]` and full https://github.com URLs
  # (tree/ and blob/ variants).
  #
  # Authentication is optional — uses the importing user's GitHub
  # OAuth token when present for the 5000/hr rate limit; falls back
  # to unauthenticated (60/hr per IP).
  class SkillImporter
    GITHUB_API = "https://api.github.com".freeze
    MAX_FILES = 50

    class Error < StandardError; end

    Source = Struct.new(:owner, :repo, :ref, :path, keyword_init: true) do
      def slug
        path.presence ? File.basename(path) : repo
      end
    end

    def self.from_github(url:, team:, by:)
      new(url: url, team: team, by: by).import
    end

    def initialize(url:, team:, by:)
      @url = url.to_s.strip
      @team = team
      @by = by
    end

    def import
      source = parse_source(@url)
      raise Error, "could not parse GitHub source: #{@url}" unless source

      files = fetch_skill_files(source)
      raise Error, "no SKILL.md found at #{display_path(source)}" unless files.key?(Skill::SKILL_MD)

      Skill.upsert_from_files(team: @team, slug: source.slug, files: files, by: @by)
    end

    private

    # Forms accepted:
    #   owner/repo
    #   owner/repo/path/to/skill
    #   https://github.com/owner/repo
    #   https://github.com/owner/repo/tree/<ref>/path/to/skill
    #   https://github.com/owner/repo/blob/<ref>/path/to/skill/SKILL.md
    def parse_source(input)
      shorthand = input.delete_prefix("https://github.com/").delete_prefix("http://github.com/")
      parts = shorthand.split("/").reject(&:empty?)
      return nil if parts.size < 2

      owner, repo = parts.shift(2)
      repo = repo.delete_suffix(".git")
      ref = nil
      path = nil

      if parts.first == "tree" || parts.first == "blob"
        kind = parts.shift
        ref = parts.shift
        path = parts.join("/")
        path = File.dirname(path) if kind == "blob" && path.end_with?(Skill::SKILL_MD)
      else
        path = parts.join("/")
      end

      Source.new(owner: owner, repo: repo, ref: ref.presence, path: path.presence)
    end

    def fetch_skill_files(source)
      walk_contents(source, source.path.to_s).each_with_object({}) do |entry, files|
        raise Error, "skill exceeds #{MAX_FILES} files" if files.size >= MAX_FILES

        rel = source.path.present? ? entry[:path].delete_prefix("#{source.path}/") : entry[:path]
        next unless Skill.valid_file_path?(rel) || rel == Skill::SKILL_MD

        files[rel] = http_get(entry[:download_url])
      end
    end

    # Recursive directory walk through GitHub's Contents API.
    def walk_contents(source, path)
      url = "#{GITHUB_API}/repos/#{source.owner}/#{source.repo}/contents/#{path}"
      url += "?ref=#{source.ref}" if source.ref

      body = JSON.parse(http_get(url, accept: "application/vnd.github+json"))
      entries = body.is_a?(Array) ? body : [ body ]

      entries.flat_map do |entry|
        case entry["type"]
        when "file"
          [ { path: entry["path"], download_url: entry["download_url"], size: entry["size"] } ]
        when "dir"
          walk_contents(source, entry["path"])
        else
          []
        end
      end
    end

    def http_get(url, accept: nil)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = accept if accept
      request["User-Agent"] = "Metis (https://github.com/chagel/metis)"
      if (token = github_token)
        request["Authorization"] = "Bearer #{token}"
      end

      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 15
      response = http.request(request)
      raise Error, "github fetch #{uri.path} -> #{response.code}" unless response.code == "200"

      response.body
    end

    def github_token
      @github_token ||= OauthBroker.bearer_for(user: @by, provider: "github")
    end

    def display_path(source)
      [ source.owner, source.repo, source.path ].compact.join("/")
    end
  end
end
