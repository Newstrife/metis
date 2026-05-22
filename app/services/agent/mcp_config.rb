module Agent
  # Renders the `.mcp.json` that pi-mcp-adapter reads, from the
  # conversation team's enabled Connectors. Each connector resolves to
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
      @conversation.team.connectors.enabled
    end

    # A connector's server entry for this conversation's member, or nil
    # to omit it: omitted when the connector has credentials but none the
    # member can use; kept (definition only) when it has none at all.
    def server_entry(connector)
      credential = connector.credential_for(@conversation.user)
      return nil if credential.nil? && connector.connector_credentials.exists?

      entry = connector.definition.deep_dup
      secrets = credential&.credential_map || {}
      return entry if secrets.empty?

      slot = connector.stdio? ? "env" : "headers"
      entry[slot] = (entry[slot] || {}).merge(secrets)
      entry
    end
  end
end
