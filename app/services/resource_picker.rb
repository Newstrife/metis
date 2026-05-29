require "net/http"
require "openssl"

# Single source of truth for connectors a project can map to. Each
# picker module declares its own metadata (label, ref-field name,
# placeholder copy, identity directive) so the form, picker partial,
# Agent::Identity, and strong-params shape all derive from one
# registry — adding a connector is one new module file + a line in
# PROVIDERS. See docs/projects.md.
module ResourcePicker
  PROVIDERS = {
    "github" => :Github,
    "linear" => :Linear
  }.freeze

  def self.for(connector_type)
    name = PROVIDERS[connector_type.to_s]
    name && const_get(name)
  end

  # Yields (provider_key, picker_module) pairs in registration order
  # for views and services that need to walk the catalog generically.
  def self.each
    return enum_for(:each) unless block_given?
    PROVIDERS.each_key { |provider| yield(provider, self.for(provider)) }
  end

  # Strong-params shape for `permit(external_refs: …)` — derived from
  # the registry so adding a connector doesn't need a controller edit.
  # Permits both the ref field (what the agent uses, e.g. Linear project
  # id) and the display field (what the human sees, e.g. project name)
  # when they differ. Picker modules without a separate DISPLAY_FIELD
  # use the ref field for both.
  def self.strong_params_shape
    PROVIDERS.keys.to_h do |provider|
      picker = self.for(provider)
      fields = [ picker::REF_FIELD.to_sym, picker::DISPLAY_FIELD.to_sym ].uniq
      [ provider.to_sym, fields ]
    end
  end

  # Net::HTTP client preconfigured with SSL + sane timeouts. The
  # explicit cert_store is non-obvious but load-bearing on platforms
  # where OpenSSL's default chain isn't picked up (macOS, Alpine).
  def self.https_client_for(uri)
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
    http.open_timeout = 5
    http.read_timeout = 10
    http
  end
end
