require "net/http"
require "json"

module OauthBroker
  module Clients
    # The Google side of the broker. Refreshes a user access token
    # against Google's OAuth token endpoint. The response includes
    # `access_token`, `expires_in`, `scope`, and `token_type` \u2014 it does
    # **not** include a new refresh token; ConnectorCredential preserves
    # the prior one.
    module Google
      TOKEN_URL = "https://oauth2.googleapis.com/token".freeze

      module_function

      def refresh(refresh_token)
        uri = URI(TOKEN_URL)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        request.set_form_data(
          client_id: GoogleApp::Config.client_id,
          client_secret: GoogleApp::Config.client_secret,
          refresh_token: refresh_token,
          grant_type: "refresh_token"
        )
        parse(https_client(uri).request(request))
      end

      def parse(response)
        raise OauthBroker::Error, "google oauth status #{response.code}" unless response.code == "200"

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
