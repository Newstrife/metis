require "net/http"
require "json"

module OauthBroker
  module Clients
    # The Linear side of the broker. Refreshes against Linear's OAuth
    # token endpoint; revokes against its revoke endpoint. Linear
    # returns `access_token`, `expires_in`, `refresh_token`, `scope`,
    # `token_type` on a refresh — the same shape OauthGrant#absorb!
    # already understands.
    module Linear
      TOKEN_URL = "https://api.linear.app/oauth/token".freeze
      REVOKE_URL = "https://api.linear.app/oauth/revoke".freeze

      module_function

      def refresh(refresh_token)
        uri = URI(TOKEN_URL)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        request.set_form_data(
          client_id: LinearApp::Config.client_id,
          client_secret: LinearApp::Config.client_secret,
          refresh_token: refresh_token,
          grant_type: "refresh_token"
        )
        parse(https_client(uri).request(request))
      end

      # POST the token to Linear's revoke endpoint. Severs the OAuth
      # grant on Linear's side so the next authorize lands as a fresh
      # consent. 200 on success; Linear returns 400 when the token is
      # already invalid — treat as success.
      def revoke(token)
        uri = URI(REVOKE_URL)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{token}"
        response = https_client(uri).request(request)
        return if response.code == "200"
        return if response.code == "400"

        raise OauthBroker::Error, "linear revoke status #{response.code}"
      end

      def parse(response)
        raise OauthBroker::Error, "linear oauth status #{response.code}" unless response.code == "200"

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
