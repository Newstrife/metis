module Previewers
  # Browser-native PDF viewer in the new tab — no inline body on the
  # card (a PDF thumbnail isn't worth the rendering cost).
  class Pdf < Base
    def self.handles?(content_type) = content_type == "application/pdf"

    def open_url(routes)
      routes.rails_blob_path(blob, disposition: "inline")
    end
  end
end
