require "net/http"
require "json"

module ResourcePicker
  # Lists the Linear projects accessible to the user through their
  # Linear OAuth grant. Linear's GraphQL API resolves `projects` to the
  # set the token can see; the picker stores the project id (a UUID
  # like `abc-123`) which we feed back to the agent through the
  # AGENTS.md project layer.
  module Linear
    GRAPHQL_URL = URI("https://api.linear.app/graphql").freeze
    QUERY = "{ projects(first: 100) { nodes { id name } } }".freeze

    module_function

    def list(user:)
      token = OauthBroker.bearer_for(user: user, provider: "linear", required_scopes: [ "read" ])
      return [] if token.blank?

      response = fetch(token)
      return [] unless response.code == "200"

      nodes = JSON.parse(response.body).dig("data", "projects", "nodes") || []
      nodes.map { |node| { value: node["id"], label: node["name"] } }
    rescue StandardError => error
      Rails.logger.warn("ResourcePicker::Linear failed for user=#{user.id}: #{error.class}: #{error.message}")
      []
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
