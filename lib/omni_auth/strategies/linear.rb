require "omniauth-oauth2"
require "digest"

module OmniAuth
  module Strategies
    # OmniAuth strategy for Linear (https://developers.linear.app/docs/oauth/authentication).
    # There is no official omniauth-linear gem, so this is a small
    # omniauth-oauth2 subclass — enough to drive the marketplace
    # "Connect Linear" button. Linear's userinfo lives behind the
    # GraphQL `viewer` query rather than a REST endpoint.
    class Linear < OmniAuth::Strategies::OAuth2
      option :name, "linear"

      option :client_options,
             site: "https://api.linear.app",
             authorize_url: "https://linear.app/oauth/authorize",
             token_url: "https://api.linear.app/oauth/token"

      # Linear requires `prompt=consent` to surface the consent screen
      # for reconnects; the connector authorize URL already passes this
      # through params, so just thread it through.
      option :authorize_options, %i[scope prompt actor]

      # Linear does strict (exact) matching on the registered redirect
      # URIs and rejects any extra query string. omniauth-oauth2's
      # default callback_url appends the request's query string
      # (`connect=…&scope=…&prompt=…`), which Linear rejects with
      # "Invalid redirect_uri parameter for the application." Strip it:
      # those params are already carried in env["omniauth.params"] and
      # don't need to round-trip through the redirect_uri.
      def callback_url
        full_host + script_name + callback_path
      end

      # omniauth-oauth2's base #authorize_params doesn't merge the
      # incoming request's query params — `option :authorize_options`
      # only declares which keys are *allowed*. omniauth-github and
      # omniauth-google-oauth2 both override authorize_params to forward
      # them, and we have to do the same or the authorize URL we send
      # to Linear ends up with no `scope` and Linear grants `read` only.
      def authorize_params
        super.tap do |params|
          %w[scope prompt actor].each do |key|
            params[key.to_sym] = request.params[key] if request.params[key]
          end
        end
      end

      # uid must always be non-nil — if the viewer query fails we fall
      # back to a hash of the access token so the auth_hash is still
      # well-formed (omniauth.auth becomes nil otherwise, and the
      # callback controller crashes downstream).
      uid { raw_info.dig("data", "viewer", "id") || Digest::SHA256.hexdigest(access_token.token)[0, 32] }

      info do
        viewer = raw_info.dig("data", "viewer") || {}
        {
          email: viewer["email"],
          name: viewer["name"],
          nickname: viewer["displayName"]
        }
      end

      # omniauth-oauth2's default credentials hash drops `scope`; without
      # this, OmniauthConnector#oauth_scope sees nothing and the grant is
      # saved with scopes: NULL — which makes covers?(catalog scopes)
      # return false and McpConfig drop the Linear connector every turn.
      # Mirror omniauth-google-oauth2's convention of surfacing it on
      # both `credentials.scope` and `extra.scope`.
      credentials do
        hash = {
          "token" => access_token.token,
          "refresh_token" => access_token.refresh_token,
          "expires_at" => access_token.expires_at,
          "expires_in" => access_token.expires_in,
          "expires" => access_token.expires?
        }
        hash["scope"] = access_token.params["scope"] if access_token.params["scope"]
        hash
      end

      extra do
        { raw_info: raw_info, scope: access_token.params["scope"] }
      end

      def raw_info
        @raw_info ||= fetch_viewer
      end

      private

      def fetch_viewer
        response = access_token.post(
          "https://api.linear.app/graphql",
          headers: {
            "Content-Type" => "application/json",
            "User-Agent" => "Metis (https://github.com/chagel/metis)"
          },
          body: { query: "{ viewer { id email name displayName } }" }.to_json
        )
        response.parsed.is_a?(Hash) ? response.parsed : {}
      rescue StandardError => error
        log_viewer_error(error)
        {}
      end

      def log_viewer_error(error)
        logger = OmniAuth.logger
        logger.warn("omniauth-linear viewer query failed: #{error.class}: #{error.message}") if logger
      end
    end
  end
end
