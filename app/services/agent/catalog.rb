module Agent
  # Provider/model options offered in the new-chat composer.
  #
  # This is a hand-maintained list — edit PROVIDERS to match what the
  # deployment's pi backend actually supports. It only drives the
  # composer's dropdowns; the chosen values land in Conversation#settings
  # and are passed through verbatim as pi's --provider/--model.
  module Catalog
    PROVIDERS = [
      {
        id: "anthropic", label: "Anthropic",
        models: [
          { id: "claude-opus-4-7",   label: "Claude Opus 4.7" },
          { id: "claude-sonnet-4-6", label: "Claude Sonnet 4.6" },
          { id: "claude-haiku-4-5",  label: "Claude Haiku 4.5" }
        ]
      },
      {
        id: "openai", label: "OpenAI",
        models: [
          { id: "gpt-5.5", label: "GPT-5.5" },
          { id: "gpt-5.1", label: "GPT-5.1" }
        ]
      },
      {
        id: "google", label: "Google",
        models: [
          { id: "gemini-3-pro",     label: "Gemini 3 Pro" },
          { id: "gemini-2.5-flash", label: "Gemini 2.5 Flash" }
        ]
      }
    ].freeze

    # [[label, id], ...] for a provider <select>.
    def self.provider_options
      PROVIDERS.map { |provider| [ provider[:label], provider[:id] ] }
    end

    # { "<provider id>" => [{ "value" =>, "label" => }, ...] } — the
    # model-select Stimulus controller reads this to repopulate the
    # model dropdown when the provider changes.
    def self.models_by_provider
      PROVIDERS.to_h do |provider|
        models = provider[:models].map { |m| { "value" => m[:id], "label" => m[:label] } }
        [ provider[:id], models ]
      end
    end

    # Provider pre-selected in the composer: the deployment default when
    # it is in the catalog, otherwise the first listed.
    def self.default_provider
      configured = Rails.application.config.x.agent.provider.presence
      ids = PROVIDERS.map { |provider| provider[:id] }
      ids.include?(configured) ? configured : ids.first
    end
  end
end
