require "csv"

module Previewers
  # Plain text, markdown, JSON, XML — anything we can render as text.
  # Markdown gets the existing markdown helper on the preview page;
  # everything else stays inside a <pre>.
  class Text < Base
    SUPPORTED = %w[
      text/plain
      text/markdown
      application/json
      application/xml
      text/xml
    ].freeze

    def self.handles?(content_type) = SUPPORTED.include?(content_type)

    def card_partial = "previewers/text_card"
    def preview_partial = "previewers/text_full"

    def open_url(routes) = routes.artifact_preview_url(blob.signed_id)

    # First N lines for the card. Streams off the blob — never loads
    # the whole file into a string.
    def head_lines(limit: INLINE_LINE_LIMIT)
      lines = []
      blob.open do |file|
        file.each_line do |line|
          lines << line
          break if lines.size >= limit
        end
      end
      lines
    end

    def markdown?
      blob.content_type == "text/markdown" ||
        blob.filename.to_s.match?(/\.(md|markdown)\z/i)
    end

    def full_content = blob.download.force_encoding("UTF-8")
  end
end
