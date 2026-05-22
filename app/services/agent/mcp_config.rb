module Agent
  # Renders the `.mcp.json` that pi-mcp-adapter reads, from a
  # conversation's enabled Connectors. Each connector's non-secret
  # definition and its encrypted credentials are merged into one inline
  # server entry. The rendered file is a per-turn projected input — the
  # Connector records are the durable source of truth. See
  # docs/connectors.md.
  class McpConfig
    # pi-mcp-adapter reads this from pi's working directory.
    FILENAME = ".mcp.json".freeze

    def initialize(conversation)
      @conversation = conversation
    end

    # The `.mcp.json` document.
    def to_h
      { "mcpServers" => connectors.to_h { |connector| [ connector.name, server_entry(connector) ] } }
    end

    # The document as a string, ready to write to FILENAME.
    def content
      JSON.pretty_generate(to_h)
    end

    private

    def connectors
      @conversation.user.connectors.enabled
    end

    # One connector's server entry: its non-secret definition, with the
    # encrypted credentials merged inline into env (stdio) or headers
    # (http).
    def server_entry(connector)
      entry = connector.definition.deep_dup
      secrets = connector.credential_map
      return entry if secrets.empty?

      slot = connector.stdio? ? "env" : "headers"
      entry[slot] = (entry[slot] || {}).merge(secrets)
      entry
    end
  end
end
