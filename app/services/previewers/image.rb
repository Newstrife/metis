module Previewers
  # SVG is intentionally NOT here — it can carry script and must not
  # render inline in the chat's origin (falls through to Fallback).
  class Image < Base
    SUPPORTED = %w[image/png image/jpeg image/gif image/webp].freeze
    VARIANT_THRESHOLD = 2.megabytes

    def self.handles?(content_type) = SUPPORTED.include?(content_type)

    def card_partial = "previewers/image_card"

    # Path helpers (not URL helpers) so this works both in the live
    # HTTP request and in a Turbo broadcast — broadcasts have no
    # request context and *_url falls back to example.org.
    def open_url(routes)
      if blob.byte_size > VARIANT_THRESHOLD
        routes.rails_representation_path(
          blob.variant(resize_to_limit: [ 2000, 2000 ]).processed
        )
      else
        routes.rails_blob_path(blob, disposition: "inline")
      end
    end
  end
end
