require "net/http"
require "json"

module GithubApp
  # The HTTP boundary to GitHub's OAuth token endpoint. Extracted as
  # its own module so OauthBroker (and the omniauth callback test
  # suite) can stub one named method rather than fake out HTTP.
  class OauthClient
    EXCHANGE_URL = "https://github.com/login/oauth/access_token".freeze

    class << self
      # Refresh an access token from a refresh token. Returns the
      # parsed response hash.
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
        raise OauthBroker::Error, "github oauth status #{response.code}" unless response.code == "200"

        parsed = JSON.parse(response.body)
        raise OauthBroker::Error, parsed["error_description"] || parsed["error"] if parsed["error"]

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
