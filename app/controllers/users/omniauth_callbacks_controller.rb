# Receives the GitHub OAuth callback for both sign-in and connector
# authorization — one flow, no separate "Connect GitHub" step. Reuses
# the OAuth tokens to upsert the member's GitHub Connector +
# ConnectorCredential so the agent can act on GitHub as them right away.
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    auth = request.env["omniauth.auth"]
    target = user_signed_in? ? attach_identity(current_user, auth) : User.from_github_omniauth(auth)
    upsert_github_connector(target, auth)

    if user_signed_in?
      redirect_to after_sign_in_path_for(target), notice: "Connected to GitHub."
    else
      sign_in_and_redirect target, event: :authentication
    end
  rescue StandardError => error
    Rails.logger.error("GitHub omniauth failed: #{error.class}: #{error.message}")
    redirect_to new_user_session_path, alert: "GitHub sign-in failed."
  end

  def failure
    redirect_to new_user_session_path, alert: "GitHub sign-in was cancelled."
  end

  private

  def attach_identity(user, auth)
    user.update!(provider: "github", uid: auth.uid.to_s)
    user
  end

  def upsert_github_connector(user, auth)
    app = ConnectorCatalog.find("github")
    connector = user.personal_team.connectors.find_or_initialize_by(catalog_key: "github")
    connector.update!(name: "github", transport: app.transport, definition: app.definition)
    credential = connector.connector_credentials.find_or_initialize_by(user: user)
    credential.assign_oauth_token!(github_token_bundle(auth.credentials))
    credential.update!(external_login: auth.info.nickname) if auth.info.nickname.present?
  end

  # Map OmniAuth credentials into the response shape ConnectorCredential
  # expects (matches the direct OAuth code-exchange response).
  def github_token_bundle(credentials)
    expires_in = credentials.expires_at ? credentials.expires_at - Time.current.to_i : nil
    {
      "access_token" => credentials.token,
      "refresh_token" => credentials.refresh_token,
      "expires_in" => expires_in,
      "scope" => credentials.respond_to?(:scope) ? credentials.scope : nil
    }.compact
  end
end
