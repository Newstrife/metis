# Provider-agnostic OAuth token broker for OauthGrants.
#
# Given an OauthGrant, returns the current access token — refreshing
# through the provider's token endpoint when the stored one is within
# `REFRESH_LEEWAY` of expiry. The bearer the MCP server receives is
# whatever this returns. Refresh writes the new token bundle back to
# the grant via OauthGrant#absorb!.
#
# `grant.provider` (e.g. "github", "google") selects which
# `Clients::*` module handles the HTTP call. See docs/connectors.md.
module OauthBroker
  class Error < StandardError; end

  CLIENTS = {
    "github" => Clients::Github,
    "google" => Clients::Google
  }.freeze

  # The base sign-in scope set per provider — the smallest set that
  # lets us identify the user (matching what config/initializers/devise.rb
  # asks for on the bare sign-in flow). Connector-specific scopes are
  # added incrementally on top by the marketplace "Connect" button.
  SIGN_IN_SCOPES = {
    "github" => [ "user:email" ],
    "google" => [ "email", "profile" ]
  }.freeze

  class << self
    # The current access token for the grant, refreshing if needed.
    # A grant whose stored access token is blank (legacy backfill row,
    # partial absorb!) must refresh even when fresh? is true — otherwise
    # we'd hand the MCP server an empty bearer instead of a 401-or-recovery.
    def access_token_for(grant)
      return grant.access_token if grant.fresh? && grant.access_token.present?

      refresh!(grant)
    end

    # Revoke the grant on the provider's side and tear down our copy.
    # Best-effort: a network failure logs and returns rather than
    # blocking the caller (the local delete still happens).
    def revoke(grant)
      client = client_for(grant.provider)
      client.revoke(grant.refresh_token || grant.access_token) if client.respond_to?(:revoke)
    rescue StandardError => error
      Rails.logger.warn(
        "OauthBroker.revoke failed for user=#{grant.user_id} provider=#{grant.provider}: " \
        "#{error.class}: #{error.message}"
      )
    end

    private

    def refresh!(grant)
      raise Error, "grant has no refresh token" if grant.refresh_token.blank?

      response = client_for(grant.provider).refresh(grant.refresh_token)
      grant.absorb!(response)
      grant.access_token
    rescue KeyError => error
      raise Error, "refresh response missing #{error.key}"
    end

    def client_for(provider)
      CLIENTS[provider] or raise Error, "unknown oauth provider #{provider.inspect}"
    end
  end
end
