module Previewers
  # An artifact previewer maps a blob to (a) a small card body shown
  # in the chat and (b) where the "Open" link points. Subclasses
  # declare which blobs they handle and supply the partial / URL
  # pieces — view code stays branch-free.
  class Base
    INLINE_LINE_LIMIT = 10
    INLINE_ROW_LIMIT = 50

    def self.handles?(_blob) = false

    attr_reader :blob

    def initialize(blob)
      @blob = blob
    end

    # Short uppercase label (RB, CSS, HTML, JSON, PNG…) for the type
    # chip. Filename extension wins because content_type detection is
    # noisy for source code.
    def kind_label
      ext = File.extname(blob.filename.to_s).delete_prefix(".")
      return ext.upcase if ext.present? && ext.length <= 5

      "FILE"
    end

    def card_partial = "previewers/fallback_card"
    def open_url(_routes) = nil
    def preview_partial = nil
  end
end
