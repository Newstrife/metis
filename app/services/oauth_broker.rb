# Provider-agnostic OAuth token broker for OauthGrants. Returns the
# current access token for a grant, refreshing through the provider's
# token endpoint when within `REFRESH_LEEWAY` of expiry. Refresh
# writes back via OauthGrant#absorb!. See docs/connectors.md.
#
# Also the single source of truth for the strategy/provider name
# split: Identity stores the omniauth strategy name ("google_oauth2"),
# OauthGrant + catalog use the canonical name ("google"). All
# translation goes through `normalize_provider` / `omniauth_strategy`.
module OauthBroker
  class Error < StandardError; end

  CLIENTS = {
    "github" => Clients::Github,
    "google" => Clients::Google,
    "linear" => Clients::Linear
  }.freeze

  STRATEGY_TO_PROVIDER = {
    "github" => "github",
    "google_oauth2" => "google",
    "linear" => "linear"
  }.freeze

  PROVIDER_TO_STRATEGY = STRATEGY_TO_PROVIDER.invert.freeze

  PROVIDERS = STRATEGY_TO_PROVIDER.values.freeze

  # The base sign-in scope set per provider — the smallest set that
  # lets us identify the user (matching what config/initializers/devise.rb
  # asks for on the bare sign-in flow). Connector-specific scopes are
  # added incrementally on top by the marketplace "Connect" button.
  # Linear is connector-only (no sign-in surface), so its base set is
  # empty — the authorize URL carries only the connector's scopes.
  SIGN_IN_SCOPES = {
    "github" => [ "user:email" ],
    "google" => [ "email", "profile" ],
    "linear" => []
  }.freeze

  class << self
    def normalize_provider(strategy)
      STRATEGY_TO_PROVIDER[strategy.to_s]
    end

    def omniauth_strategy(provider)
      PROVIDER_TO_STRATEGY[provider.to_s]
    end

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
      token = revoke_token_for(grant)
      client.revoke(token) if token.present? && client.respond_to?(:revoke)
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

    def revoke_token_for(grant)
      case grant.provider
      when "github", "linear"
        grant.access_token
      else
        grant.refresh_token || grant.access_token
      end
    end
  end
end
