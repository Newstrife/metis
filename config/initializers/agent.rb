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
