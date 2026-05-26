module Previewers
  # An artifact previewer maps a blob to (a) a small card body shown
  # in the chat and (b) where the "Open" link points. Subclasses
  # declare which content_types they handle and supply the partial /
  # URL pieces — view code stays branch-free.
  class Base
    INLINE_LINE_LIMIT = 10
    INLINE_ROW_LIMIT = 50

    def self.handles?(_content_type) = false

    attr_reader :blob

    def initialize(blob)
      @blob = blob
    end

    # Partial rendered inside the artifact card.
    def card_partial = "previewers/fallback_card"

    # Where the card's "Open" button points. Nil → no Open button
    # (the renderer can't preview the type — Download only).
    def open_url(_routes) = nil

    # Partial used by the dedicated preview page; only meaningful
    # when #open_url returns a route to that page.
    def preview_partial = nil
  end
end
