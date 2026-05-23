# Upserts the OAuth connectors a sign-in carries credentials for.
#
# One sign-in carries one OAuth token bundle, but a provider may back
# several catalog apps \u2014 a Google sign-in covers Gmail, Drive,
# Calendar, etc. all at once. This service finds every catalog app
# with `oauth_provider: <provider>` and writes the per-member
# ConnectorCredential for each. The same token bundle is shared
# across them; each MCP server projects it as a bearer at staging
# time through ConnectorCatalog::App#credential_map_for. See
# docs/connectors.md.
class OmniauthConnector
  class << self
    def upsert(user, auth, provider:)
      apps = ConnectorCatalog.all.select { |app| app.oauth? && app.oauth_provider == provider }
      bundle = token_bundle(auth.credentials)
      apps.each { |app| upsert_one(user, app, bundle, auth) }
    end

    private

    def upsert_one(user, app, bundle, auth)
      connector = user.personal_team.connectors.find_or_initialize_by(catalog_key: app.key)
      connector.update!(name: app.key, transport: app.transport, definition: app.definition)
      credential = connector.connector_credentials.find_or_initialize_by(user: user)
      credential.assign_oauth_token!(bundle)
      # Only persist a handle when the provider gives us a real one
      # (GitHub's nickname). Don't fall back to email — external_login
      # is rendered in connector UIs as a public-ish identity. The view
      # has a "Your <app> account is connected" fallback when this is
      # blank, which is the right shape for Google (no nickname).
      credential.update!(external_login: auth.info.nickname) if auth.info.nickname.present?
    end

    # Shape OmniAuth credentials into the ConnectorCredential response
    # shape (matches the direct OAuth code-exchange response).
    def token_bundle(credentials)
      expires_in = credentials.expires_at ? credentials.expires_at - Time.current.to_i : nil
      {
        "access_token" => credentials.token,
        "refresh_token" => credentials.refresh_token,
        "expires_in" => expires_in,
        "scope" => credentials.respond_to?(:scope) ? credentials.scope : nil
      }.compact
    end
  end
end
