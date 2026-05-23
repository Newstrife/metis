module ApplicationHelper
  # Render Markdown (GitHub-flavored) message content to safe HTML.
  # Raw HTML in the source is escaped (unsafe: false) and dangerous
  # link schemes are neutralized, so agent output is safe to display.
  def markdown(text)
    return "" if text.blank?

    html = Commonmarker.to_html(text,
      options: {
        render: { hardbreaks: true, escape: true, unsafe: false },
        extension: {
          strikethrough: true,
          table: true,
          autolink: true,
          tasklist: true,
          superscript: true,
          tagfilter: true
        }
      },
      plugins: { syntax_highlighter: nil })
    html = add_link_target_blank(html)
    html = strip_dangerous_uris(html)
    html.html_safe
  end

  # The compact per-message footer: turn duration and token counts.
  # "" when neither was recorded, so the footer collapses.
  def message_meta(message)
    parts = []
    parts << format_duration(message.duration) if message.duration
    parts << token_summary(message)
    parts.reject(&:blank?).join(" · ")
  end

  # Human-readable turn duration: "2.3s", "1m 04s".
  def format_duration(seconds)
    return "#{seconds.round(1)}s" if seconds < 60

    minutes, rest = seconds.divmod(60)
    format("%dm %02ds", minutes, rest)
  end

  # Summary label for an assistant turn's reasoning/tools disclosure.
  def activity_summary(message)
    return "Working…" unless message.done?

    parts = []
    parts << "Reasoning" if message.reasoning.present?
    parts << pluralize(message.tool_calls.size, "tool call") if message.tool_calls.any?
    parts.join(" · ").presence || "Activity"
  end

  # A compact per-message token line, or "" when none was recorded.
  def token_summary(message)
    return "" if message.input_tokens.blank? && message.output_tokens.blank?

    parts = []
    parts << "#{format_tokens(message.input_tokens)} in" if message.input_tokens
    parts << "#{format_tokens(message.output_tokens)} out" if message.output_tokens
    parts << "#{format_tokens(message.cache_read_tokens)} cached" if message.cache_read_tokens.to_i.positive?
    parts.join(" · ")
  end

  # Abbreviate a token count: 1530 -> "1.5k", 940 -> "940".
  def format_tokens(count)
    count = count.to_i
    return count.to_s if count < 1000

    format("%gk", (count / 100.0).round / 10.0)
  end

  # Group conversations (already ordered newest-first) by last activity
  # into calendar recency buckets for the sidebar — today, yesterday,
  # then the current week and month. Empty buckets are dropped. Matches
  # Themis's inbox_time_bucket.
  def conversation_groups(conversations)
    now = Time.current
    buckets = {
      "Today" => [], "Yesterday" => [],
      "This week" => [], "This month" => [], "Older" => []
    }
    conversations.each do |conversation|
      at = conversation.updated_at
      bucket =
        if at.to_date == now.to_date
          "Today"
        elsif at.to_date == now.yesterday.to_date
          "Yesterday"
        elsif at >= now.beginning_of_week
          "This week"
        elsif at >= now.beginning_of_month
          "This month"
        else
          "Older"
        end
      buckets[bucket] << conversation
    end
    buckets.reject { |_, list| list.empty? }
  end

  # The plain "Sign in with X" / "Connect X account" authorize path
  # for a catalog app — the *sign-in* shape, with no extra scopes.
  # Returns nil if the app's provider strategy isn't wired up.
  def omniauth_authorize_path_for(app)
    strategy = OauthBroker.omniauth_strategy(app.oauth_provider)
    return nil unless strategy
    return nil unless oauth_provider_configured?(app.oauth_provider)

    send("user_#{strategy}_omniauth_authorize_path")
  end

  # The *connect this connector* authorize path — same omniauth
  # strategy, but with the connector's required oauth_scopes added
  # on top of the base sign-in scopes, prompt=consent so the user
  # sees the new scope on the consent screen, and
  # include_granted_scopes so the new grant unions with whatever the
  # user has already authorized. The callback dispatches on the
  # `connect=<key>` param to upsert the connector marker.
  def connector_authorize_path_for(app)
    strategy = OauthBroker.omniauth_strategy(app.oauth_provider)
    return nil unless strategy
    return nil unless oauth_provider_configured?(app.oauth_provider)

    scopes = (OauthBroker::SIGN_IN_SCOPES.fetch(app.oauth_provider, []) + app.oauth_scopes).uniq.join(",")
    send("user_#{strategy}_omniauth_authorize_path",
         connect: app.key,
         scope: scopes,
         prompt: "consent",
         include_granted_scopes: true)
  end

  def oauth_provider_configured?(provider)
    case OauthBroker.normalize_provider(provider) || provider.to_s
    when "github"
      GithubApp::Config.configured?
    when "google"
      GoogleApp::Config.configured?
    else
      false
    end
  end

  private

  def add_link_target_blank(html)
    html.gsub("<a ", '<a target="_blank" rel="noopener" ')
  end

  def strip_dangerous_uris(html)
    html.gsub(/href\s*=\s*["']javascript:[^"']*["']/i, 'href="#"')
  end
end
