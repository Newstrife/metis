# One configured MCP server, owned by a user (a team, later). Each
# enabled connector becomes a `mcpServers` entry in the `.mcp.json` the
# runtime stages for a turn; pi-mcp-adapter then exposes its tools to
# the agent. See docs/connectors.md.
class Connector < ApplicationRecord
  belongs_to :owner, polymorphic: true

  encrypts :credentials

  # stdio — a `command` server entry; http — a `url` server entry.
  enum :transport, { stdio: 0, http: 1 }

  scope :enabled, -> { where(enabled: true) }

  validates :name, presence: true,
                    format: { with: /\A[a-z0-9][a-z0-9_-]*\z/i },
                    uniqueness: { scope: [ :owner_type, :owner_id ] }
  validates :transport, presence: true
  validate :definition_matches_transport

  # Secret values (API keys, tokens) for this MCP server, kept as an
  # encrypted JSON object. The runtime merges them into the staged
  # `.mcp.json` entry's env (stdio) or headers (http) — the non-secret
  # parts live in `definition`.
  def credential_map
    credentials.present? ? JSON.parse(credentials) : {}
  end

  def credential_map=(values)
    self.credentials = (values || {}).to_json
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
