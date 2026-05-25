module Agent
  # Generates a short conversation title by calling the deployment's
  # configured LLM provider directly — no pi subprocess, no adapter
  # overhead. A single cheap/fast model call is enough for this task.
  #
  # Returns a String on success, nil on any failure (misconfigured key,
  # network error, unexpected response shape). The caller is responsible
  # for providing a fallback.
  class TitleGenerator
    PROMPT = <<~PROMPT.strip
      Summarize the following message as a concise conversation title.
      Rules: 60 characters maximum, no trailing punctuation, no quotes, plain text only.
      Return just the title, nothing else.
    PROMPT

    # The fastest/cheapest model to use per provider for this one-shot call.
    TITLE_MODELS = {
      "anthropic" => "claude-haiku-4-5",
      "openai"    => "gpt-4o-mini",
      "google"    => "gemini-2.5-flash"
    }.freeze

    def self.call(message_content)
      new.call(message_content)
    end

    def call(message_content)
      return nil if message_content.blank?

      provider = Rails.application.config.x.agent.provider.presence ||
                 Agent::Catalog.default_provider
      api_key  = Rails.application.config.x.agent.api_keys.to_h[provider]
      return nil if api_key.blank?

      generate(provider, api_key, message_content.to_s.truncate(500))
    rescue => e
      Rails.logger.warn("Agent::TitleGenerator failed (#{e.class}): #{e.message}")
      nil
    end

    private

    def generate(provider, api_key, content)
      case provider
      when "anthropic" then anthropic(api_key, content)
      when "openai"    then openai(api_key, content)
      when "google"    then google(api_key, content)
      end
    end

    def anthropic(api_key, content)
      uri  = URI("https://api.anthropic.com/v1/messages")
      body = {
        model: TITLE_MODELS["anthropic"],
        max_tokens: 30,
        messages: [ { role: "user", content: "#{PROMPT}\n\n#{content}" } ]
      }
      resp = post(uri, body, {
        "x-api-key"         => api_key,
        "anthropic-version" => "2023-06-01"
      })
      resp.dig("content", 0, "text")&.strip.presence
    end

    def openai(api_key, content)
      uri  = URI("https://api.openai.com/v1/chat/completions")
      body = {
        model: TITLE_MODELS["openai"],
        max_tokens: 30,
        messages: [ { role: "user", content: "#{PROMPT}\n\n#{content}" } ]
      }
      resp = post(uri, body, { "Authorization" => "Bearer #{api_key}" })
      resp.dig("choices", 0, "message", "content")&.strip.presence
    end

    def google(api_key, content)
      uri  = URI("https://generativelanguage.googleapis.com/v1beta/models/#{TITLE_MODELS['google']}:generateContent?key=#{api_key}")
      body = { contents: [ { parts: [ { text: "#{PROMPT}\n\n#{content}" } ] } ] }
      resp = post(uri, body, {})
      resp.dig("candidates", 0, "content", "parts", 0, "text")&.strip.presence
    end

    def post(uri, body, extra_headers)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      extra_headers.each { |k, v| req[k] = v }
      req.body = body.to_json
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10
      JSON.parse(http.request(req).body)
    end
  end
end
