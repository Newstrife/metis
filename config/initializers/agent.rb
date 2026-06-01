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

# Canonical per-provider metadata — the one place each provider's display
# label and API-key env var live, keyed by pi's provider id. Both fields
# are optional and independent: `openai-codex` authenticates via the
# ChatGPT backend (no key), and keyless providers fall back to a titleized
# label. Ids and env var names mirror pi's own conventions
# (https://pi.dev/docs/latest/providers) so the same env that runs pi
# locally works for Metis.
#
#   :label -> Agent::ModelCatalogSync seeds LlmProvider#label on first sync
#   :env   -> the env var the provider's API key is read from (below)
Rails.application.config.x.agent.provider_metadata = {
  "anthropic"    => { label: "Anthropic",   env: "ANTHROPIC_API_KEY" },
  "openai"       => { label: "OpenAI",       env: "OPENAI_API_KEY" },
  "openai-codex" => { label: "OpenAI Codex" },
  "google"       => { label: "Google",       env: "GEMINI_API_KEY" },
  "deepseek"     => { label: "DeepSeek",      env: "DEEPSEEK_API_KEY" },
  "mistral"      => { env: "MISTRAL_API_KEY" },
  "groq"         => { env: "GROQ_API_KEY" },
  "cerebras"     => { env: "CEREBRAS_API_KEY" },
  "xai"          => { env: "XAI_API_KEY" },
  "openrouter"   => { env: "OPENROUTER_API_KEY" },
  "together"     => { env: "TOGETHER_API_KEY" },
  "fireworks"    => { env: "FIREWORKS_API_KEY" },
  "huggingface"  => { env: "HF_TOKEN" }
}.freeze

# Per-provider API keys, read from the environment. A conversation's
# provider id is matched against this map and the key is passed to pi as
# --api-key. A shared, deployment-level resource — Metis has no per-user
# keys. Only providers with a configured (non-blank) key end up here.
Rails.application.config.x.agent.api_keys =
  Rails.application.config.x.agent.provider_metadata.filter_map do |provider, meta|
    [ provider, ENV[meta[:env]] ] if meta[:env]
  end.to_h.compact_blank
