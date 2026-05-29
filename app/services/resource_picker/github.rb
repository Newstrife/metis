require "net/http"
require "json"

module ResourcePicker
  # Lists the repositories accessible to the user through their GitHub
  # OAuth grant. The GitHub App grant authorizes the App on whichever
  # repos the user (or an org admin) selected at install time;
  # `/user/repos` returns that intersection.
  #
  # Sorted updated-desc so the project the operator is most likely
  # working on right now is at the top of the picker. Capped at one
  # page (100) — operators with more than 100 active repos can type
  # `owner/name` directly if pagination ever becomes a real problem.
  module Github
    # Catalog metadata — read by the form, picker partial, Identity,
    # and strong-params shape. Adding a connector means defining the
    # same constants on a new module; nothing else has to change.
    KEY              = "github".freeze
    REF_FIELD        = "repo".freeze
    # Repo names like "chagel/metis" are human-readable already — the
    # value IS the display, so DISPLAY_FIELD aliases REF_FIELD.
    DISPLAY_FIELD    = REF_FIELD
    CONNECTOR_NAME   = "GitHub".freeze
    LABEL            = "GitHub repository".freeze
    PLACEHOLDER_HINT = "Select a repository…".freeze
    SUCCESS_HINT     = "When the operator says \"the repo,\" the agent knows this is it.".freeze
    EMPTY_HINT       = "to pick a repository".freeze

    LIST_URL = URI("https://api.github.com/user/repos?per_page=100&sort=updated").freeze

    module_function

    def list(user:)
      token = OauthBroker.bearer_for(user: user, provider: KEY)
      return [] if token.blank?

      response = fetch(token)
      return [] unless response.code == "200"

      JSON.parse(response.body).map { |repo| { value: repo["full_name"], label: repo["full_name"] } }
    rescue StandardError => error
      Rails.logger.warn("ResourcePicker::Github failed for user=#{user.id}: #{error.class}: #{error.message}")
      []
    end

    # One-clause summary for the team-projects catalog in AGENTS.md.
    # Returns nil when this project has no GitHub ref.
    def summary_clause(project)
      value = project.ref_for(KEY, REF_FIELD)
      value && "GitHub repo `#{value}`"
    end

    # Directive prose for the attached-project context block — load-
    # bearing, since neither GitHub nor Linear hosted MCP accepts a
    # server-side scope filter. The agent reads this to know which
    # owner/repo to pass on every tool call.
    def directive_clause(project)
      value = project.ref_for(KEY, REF_FIELD)
      value && "**Codebase:** `#{value}`. When you call GitHub MCP tools, " \
              "pass `owner` / `repo` parsed from this. When the operator " \
              "says \"the repo\" or \"the codebase,\" this is it."
    end

    def fetch(token)
      request = Net::HTTP::Get.new(LIST_URL)
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      ResourcePicker.https_client_for(LIST_URL).request(request)
    end
  end
end
