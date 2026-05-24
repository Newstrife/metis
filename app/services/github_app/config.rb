module GithubApp
  # GitHub App OAuth credentials, supplied per deployment as environment
  # variables (.env in development, foreman-loaded). The GitHub App is
  # used here through its user-to-server OAuth side: each member
  # authorizes Metis once and we hold an access + refresh token bound
  # to that member. See docs/connectors.md.
  #
  #   GITHUB_APP_CLIENT_ID      the app's OAuth client id
  #   GITHUB_APP_CLIENT_SECRET  the app's OAuth client secret
  #   GITHUB_APP_SLUG           the app's URL slug (the part after
  #                             `apps/` in https://github.com/apps/<slug>).
  #                             Optional, but without it metis can't
  #                             send the user to install the App on
  #                             their repos after the connect flow —
  #                             and the issued user-to-server token
  #                             can't see anything until they do.
  #
  # The GitHub App must have **"User-to-server token expiration"** active
  # under Settings → Optional features (new Apps default to it) — without
  # it GitHub returns no refresh token and renewals fail when the 8-hour
  # access token lapses.
  class Config
    class << self
      def client_id
        ENV.fetch("GITHUB_APP_CLIENT_ID")
      end

      def client_secret
        ENV.fetch("GITHUB_APP_CLIENT_SECRET")
      end

      def app_slug
        ENV["GITHUB_APP_SLUG"].presence
      end

      # URL that lets the user pick which account/org/repos to install
      # the App on. nil when the deployment hasn't configured the slug
      # — callers fall back to skipping the install redirect.
      def install_url
        return nil if app_slug.blank?

        "https://github.com/apps/#{app_slug}/installations/new"
      end

      # True once the deployment has registered a GitHub App and put
      # the OAuth credentials in the environment.
      def configured?
        ENV["GITHUB_APP_CLIENT_ID"].present? && ENV["GITHUB_APP_CLIENT_SECRET"].present?
      end
    end
  end
end
