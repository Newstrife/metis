module Agent
  # Renders the `.mcp.json` that pi-mcp-adapter reads, from the
  # conversation team's Connectors. Each connector resolves to
  # the conversation member's credential — their own, else the team's
  # shared one. A connector the member has no credential for is omitted;
  # a connector with no credentials at all is kept (a no-auth server).
  # The rendered file is a per-turn projected input — the Connector and
  # ConnectorCredential records are the durable source. See
  # docs/connectors.md.
  class McpConfig
    # pi-mcp-adapter reads this from pi's working directory.
    FILENAME = ".mcp.json".freeze

    def initialize(conversation)
      @conversation = conversation
    end

    # The `.mcp.json` document.
    def to_h
      entries = connectors.filter_map do |connector|
        entry = server_entry(connector)
        [ connector.name, entry ] if entry
      end
      { "mcpServers" => entries.to_h }
    end

    # The document as a string, ready to write to FILENAME.
    def content
      JSON.pretty_generate(to_h)
    end

    private

    def connectors
      @conversation.team.connectors
    end

    # A connector's server entry for this conversation's member, or nil
    # to omit it: omitted when the connector has credentials but none the
    # member can use; omitted when its catalog_key points at a missing
    # entry (data is misconfigured — better silent-drop than render a
    # likely-broken no-auth server); kept (definition only) when it has
    # no credentials at all (a no-auth server).
    def server_entry(connector)
      if connector.catalog_key.present? && connector.catalog_app.nil?
        Rails.logger.error(
          "McpConfig: connector #{connector.id} (#{connector.name}) references " \
          "catalog_key=#{connector.catalog_key.inspect} which has no entry — " \
          "dropping from .mcp.json"
        )
        return nil
      end

      credential = connector.credential_for(@conversation.user)
      return nil if credential.nil? && connector.connector_credentials.exists?

      secrets = secrets_for(connector, credential)
      return nil if secrets.nil?

      entry = connector.definition.deep_dup
      return entry if secrets.empty?

      slot = connector.stdio? ? "env" : "headers"
      entry[slot] = (entry[slot] || {}).merge(secrets)
      entry
    end

    # The header/env values a credential contributes to its connector's
    # entry. `nil` means: omit the connector entirely (no usable OAuth
    # grant, or refresh failed). `{}` means: contribute nothing (a
    # no-auth server).
    def secrets_for(connector, credential)
      return {} if credential.nil?

      app = connector.catalog_app
      return credential.credential_map unless app&.oauth?

      grant = credential.oauth_grant
      if grant.nil?
        Rails.logger.warn(
          "McpConfig: connector #{connector.id} (#{connector.name}) has no OAuth " \
          "grant for user #{@conversation.user_id} — dropping from .mcp.json"
        )
        return nil
      end

      if OauthBroker.scope_check_meaningful?(grant.provider) && !grant.covers?(app.oauth_scopes)
        Rails.logger.warn(
          "McpConfig: connector #{connector.id} (#{connector.name}) needs " \
          "#{app.oauth_scopes.inspect} but user #{@conversation.user_id}'s grant " \
          "only has #{grant.scope_set.inspect} — dropping from .mcp.json"
        )
        return nil
      end

      token = OauthBroker.access_token_for(grant)
      app.credential_map_for(token) || {}
    rescue OauthBroker::Error => error
      Rails.logger.error("McpConfig: OAuth refresh failed for connector " \
                          "#{connector.id}: #{error.message}")
      nil
    end
  end
end
