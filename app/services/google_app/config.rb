module GoogleApp
  # Google OAuth client credentials, supplied per deployment as
  # environment variables (.env in development, foreman-loaded). The
  # same client drives both \"Sign in with Google\" and authorization of
  # Google Workspace connectors (Gmail, Drive, Calendar, \u2026) \u2014 one
  # sign-in carries the scopes for every Google connector the
  # deployment exposes. See docs/connectors.md.
  #
  #   GOOGLE_OAUTH_CLIENT_ID      the OAuth 2.0 client id
  #   GOOGLE_OAUTH_CLIENT_SECRET  the OAuth 2.0 client secret
  class Config
    class << self
      def client_id
        ENV.fetch("GOOGLE_OAUTH_CLIENT_ID")
      end

      def client_secret
        ENV.fetch("GOOGLE_OAUTH_CLIENT_SECRET")
      end

      # True once the deployment has put its Google OAuth credentials
      # in the environment.
      def configured?
        ENV["GOOGLE_OAUTH_CLIENT_ID"].present? && ENV["GOOGLE_OAUTH_CLIENT_SECRET"].present?
      end
    end
  end
end
