require "test_helper"

class ArtifactPreviewerTest < ActiveSupport::TestCase
  def blob_with(content_type:, filename: "x", byte_size: 100)
    ActiveStorage::Blob.new(content_type: content_type, filename: filename, byte_size: byte_size)
  end

  test "dispatches images to the Image renderer" do
    assert_instance_of Previewers::Image,
                       ArtifactPreviewer.for(blob_with(content_type: "image/png"))
  end

  test "dispatches PDFs to the Pdf renderer" do
    assert_instance_of Previewers::Pdf,
                       ArtifactPreviewer.for(blob_with(content_type: "application/pdf"))
  end

  test "dispatches CSVs to the Csv renderer" do
    assert_instance_of Previewers::Csv,
                       ArtifactPreviewer.for(blob_with(content_type: "text/csv"))
  end

  test "dispatches plain text, markdown, and JSON to the Text renderer" do
    %w[text/plain text/markdown application/json].each do |content_type|
      assert_instance_of Previewers::Text,
                         ArtifactPreviewer.for(blob_with(content_type: content_type)),
                         "expected Text for #{content_type}"
    end
  end

  test "SVG goes to Fallback, not Image — defending against script-in-image" do
    assert_instance_of Previewers::Fallback,
                       ArtifactPreviewer.for(blob_with(content_type: "image/svg+xml"))
  end

  test "unknown types fall through to Fallback" do
    assert_instance_of Previewers::Fallback,
                       ArtifactPreviewer.for(blob_with(content_type: "application/octet-stream"))
  end

  test "Image renderer offers an open_url for non-SVG raster images" do
    image = Previewers::Image.new(blob_with(content_type: "image/jpeg"))
    routes = Object.new
    def routes.rails_blob_url(blob, **opts) = "/blob/#{blob.filename}"

    assert_equal "/blob/x", image.open_url(routes)
  end

  test "Fallback has no open_url so the card only offers Download" do
    fallback = Previewers::Fallback.new(blob_with(content_type: "application/zip"))
    assert_nil fallback.open_url(Object.new)
    assert_nil fallback.preview_partial
  end
end
