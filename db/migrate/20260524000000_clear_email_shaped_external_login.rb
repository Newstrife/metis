# Pre-refactor, OmniauthConnector#upsert_one populated
# ConnectorCredential#external_login with a fallback of
# `auth.info.nickname.presence || auth.info.email.presence`. For
# Google sign-ins (no nickname), that wrote the user's full email
# into a column the connector edit page renders as a public-ish
# handle ("Connected as @<external_login> on <App>"). The current
# code never writes email there, but legacy rows already carry the
# PII surface — clear them so the edit page falls back to its
# generic "Your <App> account is connected" wording.
#
# A handle that looks like an email (contains '@') is the
# unambiguous marker for the legacy fallback path — real handles
# (GitHub nicknames like "mgc") never contain '@'.
class ClearEmailShapedExternalLogin < ActiveRecord::Migration[8.1]
  def up
    say_with_time "Clearing email-shaped external_login values" do
      count = ConnectorCredential.where("external_login LIKE ?", "%@%")
                                 .update_all(external_login: nil)
      count
    end
  end

  def down
    # No-op — we don't track which rows we cleared, so we can't
    # restore. The cleared rows fall back to the view's generic
    # wording, which is functionally identical to never-set.
  end
end
