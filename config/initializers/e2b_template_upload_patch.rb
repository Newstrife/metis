# Workaround for e2b-ruby 0.4.0 — template build uploads fail with 403
# SignatureDoesNotMatch.
#
# E2B's API returns a GCS V2 signed URL that was computed with an
# *empty* Content-Type header, but the gem's upload_file hardcodes
# `Content-Type: application/octet-stream`. GCS recomputes the
# signature over the actual headers, sees a mismatch, and 403s.
#
# Fix: send an empty Content-Type. Verified by trying the matrix
# (octet-stream, no-header, x-tar, gzip, empty) and only empty
# returns 200. See the GCS error's StringToSign field for proof.
#
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
