require "net/http"
require "json"

module ResourcePicker
  # Lists the Linear projects accessible to the user through their
  # Linear OAuth grant. Linear's GraphQL API resolves `projects` to the
  # set the token can see; the picker stores the project id (a UUID
  # like `abc-123`) which we feed back to the agent through the
  # AGENTS.md project layer.
  module Linear
    KEY              = "linear".freeze
    REF_FIELD        = "project_id".freeze
    # Linear ids are opaque UUIDs — we also store the human-readable
    # project name so the placeholder and chip can show something the
    # operator recognizes. Synced from the picker's selected option.
    DISPLAY_FIELD    = "project_name".freeze
    CONNECTOR_NAME   = "Linear".freeze
    LABEL            = "Linear project".freeze
    PLACEHOLDER_HINT = "Select a project…".freeze
    SUCCESS_HINT     = "When the operator says \"tickets\" or \"the board,\" the agent filters Linear queries to this project.".freeze
    EMPTY_HINT       = "to pick a project".freeze

    GRAPHQL_URL = URI("https://api.linear.app/graphql").freeze
    QUERY = "{ projects(first: 100) { nodes { id name } } }".freeze

    module_function

    def list(user:)
      token = OauthBroker.bearer_for(user: user, provider: KEY, required_scopes: [ "read" ])
      return [] if token.blank?

      response = fetch(token)
      return [] unless response.code == "200"

      nodes = JSON.parse(response.body).dig("data", "projects", "nodes") || []
      nodes.map { |node| { value: node["id"], label: node["name"] } }
    rescue StandardError => error
      Rails.logger.warn("ResourcePicker::Linear failed for user=#{user.id}: #{error.class}: #{error.message}")
      []
    end

    # One-clause summary for the team-projects catalog in AGENTS.md.
    # Includes the project_name when stored so the agent has a human
    # handle to match against the operator's wording; falls back to
    # the id alone for legacy rows.
    def summary_clause(project)
      id = project.ref_for(KEY, REF_FIELD)
      return nil unless id
      name = project.ref_for(KEY, DISPLAY_FIELD)
      name.present? ? "Linear project \"#{name}\" (id `#{id}`)" : "Linear project id `#{id}`"
    end

    def directive_clause(project)
      id = project.ref_for(KEY, REF_FIELD)
      id && "**Tickets:** Linear project id `#{id}`. When the " \
            "operator says \"issues,\" \"tickets,\" or \"the board,\" filter " \
            "Linear queries to this project id."
    end

    def fetch(token)
      request = Net::HTTP::Post.new(GRAPHQL_URL)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request.body = { query: QUERY }.to_json
      ResourcePicker.https_client_for(GRAPHQL_URL).request(request)
    end
  end
end
