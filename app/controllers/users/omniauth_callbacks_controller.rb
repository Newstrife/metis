# Receives OAuth callbacks for two flows on the same omniauth URL:
#
# * **Sign in** (`POST /users/auth/<provider>`) — base scopes only,
#   creates/updates the user, records the OauthGrant. No connector
#   side-effects.
# * **Connect a connector** (`POST /users/auth/<provider>?connect=<key>
#   &scope=<base+connector>&prompt=consent&include_granted_scopes=true`)
#   — sent by the marketplace "Connect" button. Records the grant
#   (now carrying the connector's scopes) AND creates a per-member
#   ConnectorCredential marker on the team's Connector.
#
# The dispatch on `omniauth.params["connect"]` is what splits the two
# paths — sign-in carries no `connect`, connect-flow carries the
# catalog key. See docs/connectors.md.
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # Raised when a signed-in user tries to link an identity already
  # claimed by another Metis user. The controller turns this into a
  # specific alert, not the generic "Sign-in failed."
  class IdentityAlreadyLinked < StandardError; end

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
    # Capture sign-in state up front — Devise's omniauth controller
    # mutates the warden session during processing, so user_signed_in?
    # read inside a rescue is unreliable.
    was_signed_in = user_signed_in?
    return_path   = was_signed_in ? root_path : new_user_session_path

    auth   = request.env["omniauth.auth"]
    params = request.env["omniauth.params"] || {}

    target = was_signed_in ? attach_identity(current_user, auth) : User.from_omniauth(auth)
    record_grant(target, auth, provider)
    activate_connector_if_requested(target, params, auth)
    finish_sign_in(target, provider)
  rescue IdentityAlreadyLinked
    redirect_to return_path,
                alert: "This #{provider.titleize} account is already linked to another Metis user."
  rescue StandardError => error
    Rails.logger.error(
      "Omniauth(#{provider}) failed: #{error.class}: #{error.message}\n" \
      "#{error.backtrace.first(5).join("\n")}"
    )
    redirect_to new_user_session_path, alert: "Sign-in failed."
  end

  def record_grant(target, auth, provider)
    OmniauthConnector.record_grant(target, auth, provider: provider)
  rescue StandardError => error
    # Grant write failure shouldn't block a sign-in whose auth half
    # worked — the user can re-trigger Connect later. McpConfig will
    # drop the affected connector until the grant is recorded.
    Rails.logger.error(
      "Omniauth(#{provider}) grant write failed for user #{target&.id}: " \
      "#{error.class}: #{error.message}"
    )
  end

  def activate_connector_if_requested(target, params, auth)
    catalog_key = params["connect"].presence
    return if catalog_key.blank?

    app = ConnectorCatalog.find(catalog_key)
    return unless app

    OmniauthConnector.activate_connector(target, app, auth)
  rescue StandardError => error
    # Connector activation failure is non-fatal for the same reason as
    # grant write failure — the sign-in half succeeded.
    Rails.logger.error(
      "Omniauth connector activation failed for user #{target&.id} app=#{params['connect']}: " \
      "#{error.class}: #{error.message}"
    )
  end

  def finish_sign_in(target, provider)
    if user_signed_in?
      redirect_to after_sign_in_path_for(target), notice: "Connected to #{provider.titleize}."
    else
      sign_in_and_redirect target, event: :authentication
    end
  end

  def attach_identity(user, auth)
    user.identities.find_or_create_by!(provider: auth.provider, uid: auth.uid.to_s)
    user
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # The (provider, uid) is owned by a different user — the scoped
    # find_or_create_by missed it, and either the model's uniqueness
    # validation (RecordInvalid) or the DB index (RecordNotUnique)
    # rejected the insert. Identity's only validation that can fail
    # here is the unique (provider, uid), so we treat both as the
    # same "already linked elsewhere" condition.
    raise IdentityAlreadyLinked
  end
end
