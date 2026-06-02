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
      REVOKE_URL = "https://oauth2.googleapis.com/revoke".freeze

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

      # POST the token to Google's revoke endpoint. Severs the OAuth
      # grant on Google's side so the next authorize request lands as
      # a fresh consent. 200 on success, 400 with "invalid_token" if
      # already gone — both are fine.
      def revoke(token)
        uri = URI(REVOKE_URL)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.set_form_data(token: token)
        response = https_client(uri).request(request)
        return if response.code == "200"
        return if response.code == "400" && response.body.to_s.include?("invalid_token")

        raise OauthBroker::Error, "google revoke status #{response.code}"
      end

      def parse(response)
        parsed = JSON.parse(response.body) rescue {}

        if parsed["error"] == "invalid_grant"
          raise OauthBroker::InvalidGrantError,
                "google invalid_grant: #{parsed["error_description"] || "token revoked or expired"}"
        end

        unless response.code == "200"
          detail = parsed["error_description"] || parsed["error"] || response.body.to_s.truncate(200)
          raise OauthBroker::Error, "google oauth status #{response.code}: #{detail}"
        end

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
