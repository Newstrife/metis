# Move the OAuth bundle data that used to live on each
# ConnectorCredential into per-(user, provider) OauthGrant rows.
#
# Before this commit each OAuth-shaped ConnectorCredential held the
# user's tokens in its encrypted `credentials` JSON envelope (`oauth`
# key). After this commit those credentials are presence markers; the
# tokens live in OauthGrant. We walk every existing credential, union
# its scopes into the user's grant for the right provider, and keep
# the freshest access_token + a non-blank refresh_token.
#
# Idempotent: re-running compares timestamps and only overwrites with
# strictly-newer data.
class BackfillOauthGrantsFromConnectorCredentials < ActiveRecord::Migration[8.1]
  def up
    say_with_time "Backfilling OauthGrant rows from ConnectorCredential bundles" do
      count = 0
      ConnectorCredential.includes(:user, connector: :team).find_each do |cred|
        next if cred.user.nil?

        bundle = parse_bundle(cred)
        next if bundle.blank?

        catalog_app = cred.connector&.catalog_app
        provider = catalog_app&.oauth_provider
        next if provider.blank?

        absorb_bundle(cred.user, provider, bundle, catalog_app)
        count += 1
      end
      count
    end
  end

  def down
    # No reversal — the original `credentials` column is left intact
    # by `up`, so dropping the OauthGrant rows is enough to revert.
    OauthGrant.delete_all
  end

  private

  def parse_bundle(cred)
    raw = cred.credentials.presence
    return nil if raw.blank?

    JSON.parse(raw)["oauth"]
  rescue JSON::ParserError
    nil
  end

  def absorb_bundle(user, provider, bundle, catalog_app)
    grant = OauthGrant.find_or_initialize_by(user: user, provider: provider)
    incoming_expires_at = parse_iso(bundle["expires_at"])

    # Prefer the freshest access_token (latest expires_at).
    if grant.expires_at.nil? || (incoming_expires_at && incoming_expires_at > grant.expires_at)
      grant.access_token = bundle["access_token"] if bundle["access_token"].present?
      grant.expires_at   = incoming_expires_at if incoming_expires_at
    end
    grant.refresh_token = bundle["refresh_token"] if bundle["refresh_token"].present? && grant.refresh_token.blank?

    # Union scopes — bundle's `scope` if present, else fall back to
    # the catalog's required scopes for this connector (the user must
    # have granted them to have wired the connector at all). Also fold
    # in the provider's base sign-in scopes so future sign-in flows
    # don't see a regression in "what the grant covers".
    bundle_scopes  = bundle["scope"].to_s.split(/[\s,]+/).reject(&:blank?)
    fallback_scopes = bundle_scopes.empty? ? catalog_app.oauth_scopes : []
    base_scopes    = OauthBroker::SIGN_IN_SCOPES.fetch(provider, [])
    existing       = grant.scopes.to_s.split(/[\s,]+/).reject(&:blank?)
    grant.scopes   = (existing + bundle_scopes + fallback_scopes + base_scopes).uniq.join(" ")

    grant.save!
  end

  def parse_iso(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
