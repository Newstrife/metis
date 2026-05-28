require "net/http"
require "openssl"

# Lists the resources a user can pick from one of their team's
# connector OAuth grants, for the project settings UI. Each picker is
# a thin wrapper over the provider's API authenticated through
# OauthBroker.bearer_for. Returns a uniform [{value:, label:}, …]
# shape so the form partial is connector-agnostic. See
# docs/projects.md.
module ResourcePicker
  PROVIDERS = {
    "github" => :Github,
    "linear" => :Linear
  }.freeze

  def self.for(connector_type)
    name = PROVIDERS[connector_type.to_s]
    name && const_get(name)
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
