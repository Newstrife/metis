class ArtifactPreviewer
  # Order matters — first match wins. Fallback must stay last.
  RENDERERS = [
    Previewers::Image,
    Previewers::Pdf,
    Previewers::Csv,
    Previewers::Text,
    Previewers::Fallback
  ].freeze

  def self.for(blob)
    RENDERERS.find { |klass| klass.handles?(blob.content_type) }.new(blob)
  end
end
