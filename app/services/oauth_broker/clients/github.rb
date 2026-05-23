require "net/http"
require "json"

module OauthBroker
  module Clients
    # The GitHub side of the broker. Refresh delegates to the existing
    # GithubApp::OauthClient so the GitHub App OAuth flow keeps a
    # single HTTP boundary. Revoke hits the App-grant DELETE endpoint —
    # this is the call that severs the App's authorization on the
    # user's side so the next OAuth flow lands as a fresh consent.
    module Github
      REVOKE_URL_TEMPLATE = "https://api.github.com/applications/%{client_id}/grant".freeze

      module_function

      def refresh(refresh_token)
        GithubApp::OauthClient.refresh(refresh_token)
      end

      # DELETE the App's grant on this user. Requires HTTP Basic auth
      # with the App's client_id + client_secret. 204 on success.
      def revoke(token)
        uri = URI(format(REVOKE_URL_TEMPLATE, client_id: GithubApp::Config.client_id))
        request = Net::HTTP::Delete.new(uri)
        request.basic_auth(GithubApp::Config.client_id, GithubApp::Config.client_secret)
        request["Accept"] = "application/vnd.github+json"
        request.body = { access_token: token }.to_json
        request["Content-Type"] = "application/json"
        response = https_client(uri).request(request)
        return if %w[204 404].include?(response.code) # 404 = already gone — fine

        raise OauthBroker::Error, "github revoke status #{response.code}"
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
