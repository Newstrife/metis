# An encrypted secret for a Connector. A row with no user is the team's
# shared credential (a service account the whole team uses); a row with
# a user is that member's own. The runtime resolves one per member when
# staging `.mcp.json`. See docs/connectors.md.
#
# The encrypted `credentials` column is a JSON envelope with two
# optional shapes, depending on the catalog auth mode:
#
#   {"headers": {"Authorization": "Bearer …"}}   # token auth
#   {"oauth":   {"access_token": …,              # oauth auth
#                "refresh_token": …,
#                "expires_at": "…iso8601…",
#                "scope": "…"}}
class ConnectorCredential < ApplicationRecord
  belongs_to :connector
  belongs_to :user, optional: true

  encrypts :credentials

  validates :user_id, uniqueness: { scope: :connector_id }

  # The header bag (`Authorization` → "Bearer xyz") to merge into the
  # connector's `.mcp.json` entry. For token-auth credentials this is
  # the secret itself; for oauth credentials it's empty — the runtime
  # projects the live access token through the catalog's format.
  def credential_map
    envelope["headers"] || {}
  end

  def credential_map=(values)
    write_envelope("headers", values || {})
  end

  # The OAuth bundle — present iff this credential was obtained through
  # an OAuth flow. Keys: access_token, refresh_token, expires_at, scope.
  def oauth_token
    envelope["oauth"]
  end

  # Persist a token-exchange response from the OAuth provider. Accepts
  # GitHub's response shape: access_token, refresh_token, expires_in,
  # scope. `at` is the moment the response was received, used to compute
  # the absolute expiry.
  def assign_oauth_token!(response, at: Time.current)
    bundle = {
      "access_token" => response["access_token"],
      "refresh_token" => response["refresh_token"],
      "expires_at" => expires_at_from(response, at),
      "scope" => response["scope"]
    }.compact
    write_envelope("oauth", bundle)
    save!
  end

  private

  def envelope
    credentials.present? ? JSON.parse(credentials) : {}
  end

  def write_envelope(key, value)
    self.credentials = envelope.merge(key => value).to_json
  end

  def expires_at_from(response, at)
    return nil if response["expires_in"].blank?

    (at + response["expires_in"].to_i.seconds).iso8601
  end
end
