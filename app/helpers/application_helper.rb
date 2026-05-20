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

  private

  def add_link_target_blank(html)
    html.gsub("<a ", '<a target="_blank" rel="noopener" ')
  end

  def strip_dangerous_uris(html)
    html.gsub(/href\s*=\s*["']javascript:[^"']*["']/i, 'href="#"')
  end
end
