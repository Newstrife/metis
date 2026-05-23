module OauthBroker
  module Clients
    # The GitHub side of the broker \u2014 delegates to the existing
    # GithubApp::OauthClient so the GitHub App OAuth flow keeps a
    # single HTTP boundary. The refresh response shape (access_token,
    # refresh_token, expires_in, scope) matches what
    # ConnectorCredential#assign_oauth_token! already understands.
    module Github
      module_function

      def refresh(refresh_token)
        GithubApp::OauthClient.refresh(refresh_token)
      end
    end
  end
end
