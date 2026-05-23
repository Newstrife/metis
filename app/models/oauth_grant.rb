# One OAuth grant per (user, provider) — the durable home of a user's
# access + refresh tokens for a provider (Google, GitHub, …) and the
# union of every scope they've been granted across all the connectors
# wired to that provider.
#
# This is the single source of truth: ConnectorCredential rows for
# OAuth-shaped connectors are presence markers (this user wired this
# connector); the actual tokens live here. McpConfig resolves the
# bearer for a connector by looking up the user's OauthGrant for the
# connector's provider, verifying the grant's scopes cover the
# connector's required scopes, and asking OauthBroker for a fresh
# access token. See docs/connectors.md.
class OauthGrant < ApplicationRecord
  belongs_to :user

  encrypts :access_token
  encrypts :refresh_token

  validates :provider, presence: true,
                       uniqueness: { scope: :user_id },
                       inclusion: { in: OauthBroker::PROVIDERS }

  # Treat tokens within 60s of expiry as stale — leaves the broker
  # time to refresh before the MCP server sees a 401.
  REFRESH_LEEWAY = 60.seconds

  # Fallback expiry when neither the response nor the prior grant has
  # one. Matches Google's and GitHub's typical 1-hour access-token TTL.
  DEFAULT_EXPIRES_IN = 1.hour

  def fresh?
    expires_at.present? && (expires_at - Time.current) > REFRESH_LEEWAY
  end

  # The granted scopes as an array. Stored space-separated to match
  # Google's space-delimited scope wire format; we accept commas on
  # input for flexibility (some providers return them that way).
  def scope_set
    scopes.to_s.split(/[\s,]+/).reject(&:blank?)
  end

  # Does this grant cover every scope in `required`?
  def covers?(required)
    (Array(required).map(&:to_s) - scope_set).empty?
  end

  # Absorb an OAuth response from the callback or a refresh.
  #
  # `scope` in the response is authoritative when present — replace,
  # don't union, or covers? will keep returning true for a scope the
  # user just revoked on the consent screen. Absent (refresh, grant
  # unchanged) preserves the prior set. `refresh_token` may also be
  # omitted (Google does on refresh); preserve the prior one.
  def absorb!(response, at: Time.current)
    self.access_token = response["access_token"] if response["access_token"].present?
    self.refresh_token = response["refresh_token"] if response["refresh_token"].present?
    # Order matters: prefer the response's expires_in, fall back to the
    # prior value, and only THEN default to the provider's typical
    # 1-hour TTL. Without that last fallback, a grant with neither a
    # prior expires_at nor an incoming expires_in (legacy backfill,
    # provider quirk) is stuck with expires_at nil — fresh? returns
    # false forever, so OauthBroker refreshes on every chat turn
    # (refresh-stampede + provider rate limit).
    self.expires_at = expires_at_from(response, at) || expires_at || (at + DEFAULT_EXPIRES_IN)
    self.scopes = adopt_scopes(response["scope"])
    save!
  end

  # Drop a scope set from the grant — used when a connector is
  # disconnected and its scopes are no longer needed locally. The
  # Google grant itself is untouched (revocation is a separate
  # concern, handled when the last OAuth connector for the provider
  # is disconnected).
  def remove_scopes!(scopes_to_remove)
    self.scopes = (scope_set - Array(scopes_to_remove).map(&:to_s)).join(" ")
    save!
  end

  private

  def adopt_scopes(incoming)
    return scopes if incoming.blank?

    incoming.to_s.split(/[\s,]+/).reject(&:blank?).uniq.join(" ")
  end

  def expires_at_from(response, at)
    return nil if response["expires_in"].blank?

    at + response["expires_in"].to_i.seconds
  end
end
