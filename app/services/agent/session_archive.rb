require "tempfile"

module Agent
  # Durable, worker-independent persistence for a conversation's agent
  # scratch scope — pi's session directory *and* its working directory
  # (see Agent::Workspace).
  #
  # The durable copy is a gzipped tar of the whole scope, held as the
  # conversation's Active Storage attachment — so any job worker, and
  # any runtime, can rehydrate it regardless of where the previous turn
  # ran. It is the conversation's source of truth; the runtime's sandbox
  # (local scratch dir, or an E2B microVM) is disposable.
  #
  #   restore/store   — local-directory convenience (Runtime::Local)
  #   with_archive/attach — blob access for runtimes that tar elsewhere
  #                         (Runtime::E2b tars inside the sandbox)
  class SessionArchive
    FILENAME = "pi-session.tar.gz".freeze
    CONTENT_TYPE = "application/gzip".freeze

    class ArchiveError < StandardError; end

    class << self
      def archived?(conversation)
        conversation.pi_session_archive.attached?
      end

      # Yield a local path to the downloaded archive. No-op (no yield)
      # when the conversation has no archive yet — the first turn.
      def with_archive(conversation)
        return unless archived?(conversation)

        conversation.pi_session_archive.open do |archive|
          yield archive.path
        end
      end

      # Attach the gzipped tar at `path`, replacing any prior archive.
      def attach(conversation, path)
        conversation.pi_session_archive.attach(
          io: File.open(path), filename: FILENAME, content_type: CONTENT_TYPE
        )
      end

      # --- local-directory convenience (Runtime::Local) ----------------

      # Unpack the conversation's stored archive into `dir`.
      def restore(conversation, into:)
        with_archive(conversation) { |path| extract(path, into) }
      end

      # Tar `dir` and attach it. No-op when `dir` is empty (nothing ran).
      def store(conversation, from:)
        return unless Dir.exist?(from) && !Dir.empty?(from)

        Tempfile.create([ "pi-session", ".tar.gz" ]) do |tmp|
          compress(from, tmp.path)
          attach(conversation, tmp.path)
        end
      end

      private

      def compress(dir, archive_path)
        ok = system("tar", "-czf", archive_path.to_s, "-C", dir.to_s, ".", %i[out err] => File::NULL)
        raise ArchiveError, "failed to archive pi session dir #{dir}" unless ok
      end

      def extract(archive_path, dir)
        ok = system("tar", "-xzf", archive_path.to_s, "-C", dir.to_s, %i[out err] => File::NULL)
        raise ArchiveError, "failed to extract pi session archive into #{dir}" unless ok
      end
    end
  end
end
