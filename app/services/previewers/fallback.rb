module Previewers
  # Catches anything no other renderer claims: download-only.
  class Fallback < Base
    def self.handles?(_content_type) = true
  end
end
