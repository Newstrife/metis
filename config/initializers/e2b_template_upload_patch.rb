# Workaround for e2b-ruby 0.4.0: GCS signed URL is computed with empty
# Content-Type but the gem sends `application/octet-stream`, yielding 403.
# Remove once https://github.com/ya-luotao/e2b-ruby fixes upstream.

require "e2b"
require "faraday"

module E2B
  class Template
    class << self
      def upload_file(template, file_name:, url:, resolve_symlinks:, source_location: nil)
        tarball = build_tar_archive(template, file_name, resolve_symlinks: resolve_symlinks)
        response = Faraday.put(url) do |req|
          # Must match what E2B signed (empty Content-Type).
          req.headers["Content-Type"] = ""
          req.body = tarball
        end

        return if response.success?

        raise file_upload_error("Failed to upload file: #{response.status}", source_location: source_location)
      rescue Faraday::Error => e
        raise file_upload_error("Failed to upload file: #{e.message}", source_location: source_location)
      end
    end
  end
end
