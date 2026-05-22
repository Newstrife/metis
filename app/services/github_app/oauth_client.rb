require "net/http"
require "json"

module GithubApp
  # The HTTP boundary to GitHub's OAuth endpoints. Extracted as its own
  # module so callers (TokenService, the connect controller) can be
  # tested by stubbing two named methods rather than faking HTTP.
  class OauthClient
    EXCHANGE_URL = "https://github.com/login/oauth/access_token".freeze

    class << self
      # Exchange an authorization code for a user access-token bundle.
      def exchange_code(code, redirect_uri:)
        post(code: code, redirect_uri: redirect_uri, grant_type: "authorization_code")
      end

      # Refresh an access token from a refresh token.
      def refresh(refresh_token)
        post(refresh_token: refresh_token, grant_type: "refresh_token")
      end

      private

      def post(form)
        body = form.merge(client_id: Config.client_id, client_secret: Config.client_secret)
        uri = URI(EXCHANGE_URL)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        request.set_form_data(body)
        parse(https_client(uri).request(request))
      end

      def parse(response)
        raise TokenService::Error, "github oauth status #{response.code}" unless response.code == "200"

        parsed = JSON.parse(response.body)
        raise TokenService::Error, parsed["error_description"] || parsed["error"] if parsed["error"]

        parsed
      end

      def https_client(uri)
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
        http.open_timeout = 5
        http.read_timeout = 10
        http
      end
    end
  end
end
