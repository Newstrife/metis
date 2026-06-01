# Agent runtime configuration.
#
# The runtime — *where* the coding agent runs — is a per-deployment
# choice. See
# Agent::Runtime.
#
#   :local  — pi as a local subprocess. NOT isolated; single-operator /
#             development only.
#   :docker — pi in a Docker container. Namespace-isolated; self-hosted,
#             needs a Docker daemon and an image (see docker:image).
#   :e2b    — pi inside a secure E2B microVM. The isolated runtime;
#             requires E2B_API_KEY and a template with pi baked in.
Rails.application.config.x.agent.runtime =
  ENV.fetch("METIS_AGENT_RUNTIME", "local").to_sym

# E2B template (image) used by the :e2b runtime — should have pi
# installed. See the e2b:template rake task for the build definition.
Rails.application.config.x.agent.e2b_template =
  ENV.fetch("METIS_E2B_TEMPLATE", "base")

# Idle window after which a paused E2B sandbox is evicted (killed) by
# EvictPausedSandboxesJob. E2B keeps paused sandboxes indefinitely
# unless we tell it otherwise (docs/coding-runtime.md), so this knob
# bounds how long a long-idle conversation's working tree survives —
# the next turn provisions a fresh sandbox.
Rails.application.config.x.agent.e2b_eviction_window =
  ENV.fetch("METIS_E2B_EVICTION_HOURS", "24").to_i.hours

# Docker image used by the :docker runtime — pi baked in. Build it with
# the docker:image rake task.
Rails.application.config.x.agent.docker_image =
  ENV.fetch("METIS_DOCKER_IMAGE", "metis-pi")

# pi's default provider/model — used when a conversation sets none of
# its own (the new-chat composer normally does). See
# Agent::Adapters::Pi#credential_args.
Rails.application.config.x.agent.provider = ENV["METIS_AGENT_PROVIDER"].presence
Rails.application.config.x.agent.model = ENV["METIS_AGENT_MODEL"].presence

# Per-provider API keys, read from the environment. A conversation's
# provider id is matched against this map and the key is passed to pi
# as --api-key. These are a shared, deployment-level resource — Metis
# has no per-user keys.
#
# Provider ids and env var names mirror pi's own conventions
# (https://pi.dev/docs/latest/providers) so the same env that runs pi
# locally works for Metis. Only entries with a non-blank value end up
# in the map.
# The provider -> env-var-name map is the single source of truth: the key
# values below read from it, and Agent::ModelCatalogSync derives the
# control-session env from it too (so a new provider is added in one place).
Rails.application.config.x.agent.api_key_env_names = {
  "anthropic"   => "ANTHROPIC_API_KEY",
  "openai"      => "OPENAI_API_KEY",
  "google"      => "GEMINI_API_KEY",
  "deepseek"    => "DEEPSEEK_API_KEY",
  "mistral"     => "MISTRAL_API_KEY",
  "groq"        => "GROQ_API_KEY",
  "cerebras"    => "CEREBRAS_API_KEY",
  "xai"         => "XAI_API_KEY",
  "openrouter"  => "OPENROUTER_API_KEY",
  "together"    => "TOGETHER_API_KEY",
  "fireworks"   => "FIREWORKS_API_KEY",
  "huggingface" => "HF_TOKEN"
}
Rails.application.config.x.agent.api_keys =
  Rails.application.config.x.agent.api_key_env_names
       .transform_values { |env_name| ENV[env_name] }
       .compact_blank
