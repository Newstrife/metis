module Connectors
  # The GitHub OAuth connect flow (docs/connectors.md). #start sends
  # the current user to GitHub's authorize URL with a signed `state`;
  # GitHub returns to #callback with a code and that state, which we
  # exchange for an access + refresh token bound to the same user and
  # stored as a per-member ConnectorCredential on the team's GitHub
  # connector.
  class GithubController < ApplicationController
    CATALOG_KEY = "github".freeze
    AUTHORIZE_URL = "https://github.com/login/oauth/authorize".freeze

    def start
      unless GithubApp::Config.configured?
        return redirect_to connectors_path,
                           alert: "GitHub OAuth is not configured for this deployment."
      end

      state = GithubApp::StateToken.generate(user_id: current_user.id)
      redirect_to authorize_url(state), allow_other_host: true
    end

    def callback
      return reject("Could not verify the GitHub connection.") if verify_state != current_user.id
      return reject("GitHub authorization was not completed.") if params[:code].blank?

      response = GithubApp::OauthClient.exchange_code(params[:code], redirect_uri: connector_github_callback_url)
      connector = upsert_connector
      credential = connector.connector_credentials.find_or_initialize_by(user: current_user)
      credential.assign_oauth_token!(response)
      redirect_to edit_connector_path(connector), notice: "GitHub connected."
    rescue GithubApp::TokenService::Error => error
      Rails.logger.error("Connectors::GithubController#callback: #{error.message}")
      reject("GitHub connection failed.")
    end

    private

    def authorize_url(state)
      query = URI.encode_www_form(
        client_id: GithubApp::Config.client_id, state: state,
        redirect_uri: connector_github_callback_url
      )
      "#{AUTHORIZE_URL}?#{query}"
    end

    def verify_state
      GithubApp::StateToken.verify(params[:state])
    rescue GithubApp::StateToken::InvalidError
      nil
    end

    # The team's GitHub connector — created on the first member's
    # connect, reused on every subsequent member's. Each member adds
    # their own ConnectorCredential.
    def upsert_connector
      app = ConnectorCatalog.find(CATALOG_KEY)
      connector = current_user.personal_team.connectors.find_or_initialize_by(catalog_key: CATALOG_KEY)
      connector.update!(name: CATALOG_KEY, transport: app.transport, definition: app.definition)
      connector
    end

    def reject(message)
      redirect_to connectors_path, alert: message
    end
  end
end
