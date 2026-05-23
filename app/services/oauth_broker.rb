# Provider-agnostic OAuth token broker for connector credentials.
#
# Given a `ConnectorCredential` carrying a stored access + refresh
# token, returns the current access token \u2014 refreshing through the
# provider's token endpoint when the stored one is within
# `REFRESH_LEEWAY` of expiry. The bearer the MCP server receives is
# whatever this returns. See docs/connectors.md.
#
# The provider is the catalog `oauth_provider` key (e.g. "github",
# "google"); each provider is a `Clients::*` module that knows how to
# call its token endpoint.
module OauthBroker
  class Error < StandardError; end

  REFRESH_LEEWAY = 60.seconds

  CLIENTS = {
    "github" => Clients::Github,
    "google" => Clients::Google
  }.freeze

  class << self
    # The current access token for the credential, refreshing if needed.
    # `provider` is the catalog `oauth_provider` (which client to ask).
    def access_token_for(credential, provider:)
      bundle = credential.oauth_token
      raise Error, "credential has no oauth bundle" if bundle.blank?

      return bundle["access_token"] if fresh?(bundle)

      refresh!(credential, bundle["refresh_token"], provider)
    end

    private

    def fresh?(bundle)
      return false if bundle["expires_at"].blank?

      Time.iso8601(bundle["expires_at"]) - Time.current > REFRESH_LEEWAY
    rescue ArgumentError
      false
    end

    def refresh!(credential, refresh_token, provider)
      raise Error, "credential has no refresh token" if refresh_token.blank?

      client = CLIENTS[provider] or raise Error, "unknown oauth provider #{provider.inspect}"
      response = client.refresh(refresh_token)
      credential.assign_oauth_token!(response)
      credential.oauth_token.fetch("access_token")
    rescue KeyError => error
      raise Error, "refresh response missing #{error.key}"
    end
  end
end
