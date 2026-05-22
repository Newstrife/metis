# An encrypted secret for a Connector. A row with no user is the team's
# shared credential (a service account the whole team uses); a row with
# a user is that member's own. The runtime resolves one per member when
# staging `.mcp.json`. See docs/connectors.md.
class ConnectorCredential < ApplicationRecord
  belongs_to :connector
  belongs_to :user, optional: true

  encrypts :credentials

  validates :user_id, uniqueness: { scope: :connector_id }

  # The secret env/header values as a hash; the runtime merges them into
  # the connector's `.mcp.json` entry. Stored as an encrypted JSON object.
  def credential_map
    credentials.present? ? JSON.parse(credentials) : {}
  end

  def credential_map=(values)
    self.credentials = (values || {}).to_json
  end
end
