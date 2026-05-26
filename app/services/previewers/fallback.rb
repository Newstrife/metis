module Previewers
  # Catches anything no other renderer claims: download-only.
  class Fallback < Base
    def self.handles?(_blob) = true
  end
end
