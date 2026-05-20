# Agent runtime configuration.
#
# The runtime — *where* the coding agent runs — is a per-deployment
# choice (unlike the backend, which is per-conversation). See
# Agent::Runtime.
#
#   :local — pi as a local subprocess. NOT isolated; single-operator /
#            development only.
#   :e2b   — pi inside a secure E2B microVM. The isolated runtime;
#            requires E2B_API_KEY and a template with pi baked in.
Rails.application.config.x.agent.runtime =
  ENV.fetch("METIS_AGENT_RUNTIME", "local").to_sym

# E2B template (image) used by the :e2b runtime — should have pi
# installed. See the e2b:template rake task for the build definition.
Rails.application.config.x.agent.e2b_template =
  ENV.fetch("METIS_E2B_TEMPLATE", "base")

# pi's default provider/model — used when a conversation sets none of
# its own (the new-chat composer normally does). See
# Agent::Adapters::Pi#credential_args.
Rails.application.config.x.agent.provider = ENV["METIS_AGENT_PROVIDER"].presence
Rails.application.config.x.agent.model = ENV["METIS_AGENT_MODEL"].presence

# Per-provider API keys, read from the environment (.env in development,
# loaded by foreman for bin/dev; real env vars in production). A
# conversation's provider is matched against this map and the key is
# passed to pi as --api-key. A per-user ApiKey overrides it.
Rails.application.config.x.agent.api_keys = {
  "anthropic" => ENV["ANTHROPIC_API_KEY"],
  "openai"    => ENV["OPENAI_API_KEY"],
  "google"    => ENV["GOOGLE_API_KEY"]
}.compact_blank
