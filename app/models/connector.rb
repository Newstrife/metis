# One configured MCP server, owned by a team. Each connector becomes a
# `mcpServers` entry in the `.mcp.json` the runtime stages for a turn;
# pi-mcp-adapter then exposes its tools to the agent. The non-secret
# server definition lives here; secrets are separate
# ConnectorCredentials, shared or per-member. See docs/connectors.md.
class Connector < ApplicationRecord
  belongs_to :team
  has_many :connector_credentials, dependent: :destroy

  # stdio — a `command` server entry; http — a `url` server entry.
  enum :transport, { stdio: 0, http: 1 }

  validates :name, presence: true,
                    format: { with: /\A[a-z0-9][a-z0-9_-]*\z/i },
                    uniqueness: { scope: :team_id }
  validates :transport, presence: true
  validate :definition_matches_transport

  # The credential a given member connects with: their own if set, else
  # the team's shared credential, else nil.
  def credential_for(user)
    connector_credentials.find_by(user: user) || connector_credentials.find_by(user: nil)
  end

  # The marketplace app this connector was created from, or nil for a
  # custom connector. See ConnectorCatalog, docs/connectors.md.
  def catalog_app
    ConnectorCatalog.find(catalog_key)
  end

  private

  # A stdio server entry needs a command; an http one needs a url.
  def definition_matches_transport
    return unless transport

    required = stdio? ? "command" : "url"
    return if definition[required].present?

    errors.add(:definition, "must include a #{required} for a #{transport} connector")
  end
end
