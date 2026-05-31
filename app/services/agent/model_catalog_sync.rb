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
      session = PiAgent.session(args: %w[--mode rpc])
      session.available_models
    rescue StandardError => e
      Rails.logger.warn("Agent::ModelCatalogSync fetch failed: #{e.message}")
      nil
    ensure
      session&.close
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
