require "net/http"
require "json"

module GithubApp
  # Fetches the authenticated user's GitHub profile (`GET /user`) so the
  # connect flow can capture the member's `login` and store it on the
  # ConnectorCredential. The login is decorative — used by the connector
  # page and the agent context. Failure is the caller's responsibility
  # to make non-fatal; the OAuth bundle itself is still valid.
  class UserInfo
    USER_URL = "https://api.github.com/user".freeze

    class << self
      # Returns the parsed `/user` body for the access token; raises
      # TokenService::Error on any failure (HTTP, network, JSON).
      def fetch(access_token)
        uri = URI(USER_URL)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Accept"] = "application/vnd.github+json"
        request["X-GitHub-Api-Version"] = "2022-11-28"

        response = https_client(uri).request(request)
        raise TokenService::Error, "github /user status #{response.code}" unless response.code == "200"

        JSON.parse(response.body)
      rescue TokenService::Error
        raise
      rescue StandardError => error
        raise TokenService::Error, "#{error.class}: #{error.message}"
      end

      private

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
