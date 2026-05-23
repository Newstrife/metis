# Receives OAuth callbacks for sign-in and connector authorization in
# one flow \u2014 the same OAuth tokens that authenticate the user also
# wire up every catalog connector backed by that provider (GitHub: the
# GitHub MCP server; Google: Gmail, Drive, Calendar, \u2026). See
# docs/connectors.md.
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    handle("github")
  end

  def google_oauth2
    handle("google")
  end

  def failure
    redirect_to new_user_session_path, alert: "Sign-in was cancelled."
  end

  private

  def handle(provider)
    auth = request.env["omniauth.auth"]
    target = user_signed_in? ? attach_identity(current_user, auth) : User.from_omniauth(auth)
    OmniauthConnector.upsert(target, auth, provider: provider)

    if user_signed_in?
      redirect_to after_sign_in_path_for(target), notice: "Connected to #{provider.titleize}."
    else
      sign_in_and_redirect target, event: :authentication
    end
  rescue StandardError => error
    Rails.logger.error("Omniauth(#{provider}) failed: #{error.class}: #{error.message}")
    redirect_to new_user_session_path, alert: "Sign-in failed."
  end

  def attach_identity(user, auth)
    user.identities.find_or_create_by!(provider: auth.provider, uid: auth.uid.to_s)
    user
  end
end
