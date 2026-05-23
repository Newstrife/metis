# Receives OAuth callbacks for sign-in and connector authorization in
# one flow — the same OAuth tokens that authenticate the user also
# wire up every catalog connector backed by that provider (GitHub: the
# GitHub MCP server; Google: Gmail, Drive, Calendar, …). See
# docs/connectors.md.
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

    auth = request.env["omniauth.auth"]
    target = was_signed_in ? attach_identity(current_user, auth) : User.from_omniauth(auth)
    upsert_connectors(target, auth, provider)
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

  # Connector wiring is best-effort: a transient failure here must not
  # block a sign-in whose auth half succeeded — the user can re-trigger
  # the connector flow from the marketplace. We log and continue.
  def upsert_connectors(target, auth, provider)
    OmniauthConnector.upsert(target, auth, provider: provider)
  rescue StandardError => error
    Rails.logger.error(
      "Omniauth(#{provider}) connector upsert failed for user #{target&.id}: " \
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
