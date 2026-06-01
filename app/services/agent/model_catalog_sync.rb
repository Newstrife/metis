require "shellwords"

module Agent
  # Mirrors pi's available-models catalog into LlmProvider / LlmModel rows.
  #
  # pi (get_available_models) is the source of truth for *what exists*; the
  # rows add what pi has no concept of — operator curation (enabled, label,
  # ordering, the deployment default). Curation is sticky: a refresh updates
  # pi-derived metadata but never clobbers enabled / label / position /
  # is_default on rows that already exist. Models pi no longer reports are
  # kept (and shown stale by last_seen_at), never deleted — a key may just
  # be temporarily unset.
  #
  # Deployment-level, like provider API keys (VISION rule 4).
  module ModelCatalogSync
    # pi reports a provider id but no display name; seed a nice label for
    # the casing-sensitive ones (titleize botches "deepseek"/"openai-codex").
    # Seed-only — an admin's later label edits survive refreshes.
    PROVIDER_LABELS = {
      "anthropic"    => "Anthropic",
      "openai"       => "OpenAI",
      "openai-codex" => "OpenAI Codex",
      "google"       => "Google",
      "deepseek"     => "DeepSeek"
    }.freeze

    API_KEY_ENV = {
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
    }.freeze

    module_function

    # Returns { providers:, models:, ok: } — ok false when pi was
    # unreachable (callers surface this; nothing is mutated in that case).
    def call
      payload = fetch_models
      return { providers: 0, models: 0, ok: false } if payload.blank?

      seen = 0
      payload.group_by { |model| model["provider"] }.each do |provider_key, group|
        provider = upsert_provider(provider_key)
        group.each do |model|
          upsert_model(provider, model)
          seen += 1
        end
      end
      { providers: LlmProvider.count, models: seen, ok: true }
    end

    def fetch_models
      case Rails.application.config.x.agent.runtime&.to_sym
      when :docker then fetch_models_from_docker
      when :e2b    then fetch_models_from_e2b
      else fetch_models_from_local
      end
    rescue StandardError => e
      Rails.logger.warn("Agent::ModelCatalogSync fetch failed: #{e.message}")
      nil
    end

    def fetch_models_from_local
      session = PiAgent.session(args: %w[--mode rpc], env: api_key_env)
      session.available_models
    ensure
      session&.close
    end

    def fetch_models_from_docker
      session = PiAgent.session(
        bin: "docker", args: docker_args, env: api_key_env
      )
      session.available_models
    ensure
      session&.close
    end

    def fetch_models_from_e2b
      sandbox = E2B::Sandbox.create(
        template: Rails.application.config.x.agent.e2b_template,
        timeout: Agent::Runtime::E2b::SANDBOX_TIMEOUT
      )
      command = Shellwords.join(%w[pi --mode rpc])
      transport = lambda do |on_message:, on_stderr:|
        Agent::Runtime::E2bTransport.new(
          sandbox: sandbox, command: command, envs: api_key_env,
          on_message: on_message, on_stderr: on_stderr
        )
      end
      session = PiAgent.session(transport_factory: transport)
      session.available_models
    ensure
      session&.close
      sandbox&.kill
    end

    def docker_args
      [
        "run", "--rm", "-i",
        "--pull", "never",
        "--env", "HOME=/tmp",
        *api_key_env.keys.flat_map { |name| [ "--env", name ] },
        "--memory", "2g", "--cpus", "2", "--pids-limit", "512",
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        Rails.application.config.x.agent.docker_image,
        "pi", "--mode", "rpc"
      ]
    end

    def api_key_env
      Rails.application.config.x.agent.api_keys.to_h.filter_map do |provider, value|
        name = API_KEY_ENV[provider]
        [ name, value ] if name && value.present?
      end.to_h
    end

    def upsert_provider(key)
      provider = LlmProvider.find_or_initialize_by(key: key)
      if provider.new_record?
        provider.label = PROVIDER_LABELS[key] || key.to_s.titleize
        provider.position = LlmProvider.maximum(:position).to_i + 1
      end
      provider.save!
      provider
    end

    def upsert_model(provider, data)
      model = provider.llm_models.find_or_initialize_by(key: data["id"])
      if model.new_record?
        model.label = data["name"].presence || data["id"]
        model.position = provider.llm_models.maximum(:position).to_i + 1
      end
      model.context_window  = data["contextWindow"]
      model.max_tokens      = data["maxTokens"]
      model.reasoning       = data["reasoning"] ? true : false
      model.input_modalities = data["input"] || []
      model.cost            = data["cost"] || {}
      model.last_seen_at    = Time.current
      model.save!
      model
    end
  end
end
