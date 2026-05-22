module GithubApp
  # Returns the current GitHub user access token for a ConnectorCredential,
  # transparently refreshing through the stored refresh token when the
  # access token is within a minute of expiry. The bearer the GitHub MCP
  # server receives is whatever this returns. See docs/connectors.md.
  class TokenService
    REFRESH_LEEWAY = 60.seconds

    class Error < StandardError; end

    class << self
      # The current access token for the credential. May trigger a
      # refresh + persist if the stored access token has (nearly) expired.
      def access_token_for(credential)
        bundle = credential.oauth_token
        raise Error, "credential has no oauth bundle" if bundle.blank?

        return bundle["access_token"] if fresh?(bundle)

        refresh!(credential, bundle["refresh_token"])
      end

      private

      def fresh?(bundle)
        return false if bundle["expires_at"].blank?

        Time.iso8601(bundle["expires_at"]) - Time.current > REFRESH_LEEWAY
      rescue ArgumentError
        false
      end

      def refresh!(credential, refresh_token)
        raise Error, "credential has no refresh token" if refresh_token.blank?

        response = OauthClient.refresh(refresh_token)
        credential.assign_oauth_token!(response)
        response.fetch("access_token")
      rescue KeyError => error
        raise Error, "refresh response missing #{error.key}"
      end
    end
  end
end
