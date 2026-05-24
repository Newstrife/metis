module LinearApp
  # Linear OAuth credentials, supplied per deployment as environment
  # variables (.env in development, foreman-loaded). Linear is wired
  # only as a connector (no "Sign in with Linear") — the OAuth client
  # exists solely to mint per-user access tokens for mcp.linear.app.
  # See docs/connectors.md.
  #
  #   LINEAR_CLIENT_ID      the app's OAuth client id
  #   LINEAR_CLIENT_SECRET  the app's OAuth client secret
  #
  # Register the app at https://linear.app/settings/api/applications and
  # set the redirect URL to <host>/users/auth/linear/callback.
  class Config
    class << self
      def client_id
        ENV.fetch("LINEAR_CLIENT_ID")
      end

      def client_secret
        ENV.fetch("LINEAR_CLIENT_SECRET")
      end

      def configured?
        ENV["LINEAR_CLIENT_ID"].present? && ENV["LINEAR_CLIENT_SECRET"].present?
      end
    end
  end
end
