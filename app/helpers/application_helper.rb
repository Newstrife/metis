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

  private

  def add_link_target_blank(html)
    html.gsub("<a ", '<a target="_blank" rel="noopener" ')
  end

  def strip_dangerous_uris(html)
    html.gsub(/href\s*=\s*["']javascript:[^"']*["']/i, 'href="#"')
  end
end
