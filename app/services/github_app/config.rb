module GithubApp
  # GitHub App OAuth credentials, supplied per deployment as environment
  # variables (.env in development, foreman-loaded). The GitHub App is
  # used here only through its user-to-server OAuth side: each member
  # authorizes Metis once and we hold an access + refresh token bound
  # to that member. See docs/connectors.md.
  #
  #   GITHUB_APP_CLIENT_ID      the app's OAuth client id
  #   GITHUB_APP_CLIENT_SECRET  the app's OAuth client secret
  #
  # The GitHub App must have **"Expire user authorization tokens"**
  # enabled in its settings — otherwise GitHub returns no refresh token
  # and renewals fail when the 8-hour access token lapses.
  class Config
    class << self
      def client_id
        ENV.fetch("GITHUB_APP_CLIENT_ID")
      end

      def client_secret
        ENV.fetch("GITHUB_APP_CLIENT_SECRET")
      end

      # True once the deployment has registered a GitHub App and put
      # the OAuth credentials in the environment.
      def configured?
        ENV["GITHUB_APP_CLIENT_ID"].present? && ENV["GITHUB_APP_CLIENT_SECRET"].present?
      end
    end
  end
end
