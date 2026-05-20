require "tempfile"

module Agent
  # Durable, worker-independent persistence for a conversation's agent
  # scratch scope — pi's session directory *and* its working directory
  # (see Agent::Workspace).
  #
  # The local scope is scratch (under tmp/). The durable copy is a
  # gzipped tar of the whole scope, held as the conversation's Active
  # Storage attachment — so any job worker can rehydrate it regardless
  # of which worker ran the previous turn.
  #
  #   SessionArchive.restore(conversation, into: scratch_dir)  # before a run
  #   SessionArchive.store(conversation, from: scratch_dir)    # after a run
  class SessionArchive
    FILENAME = "pi-session.tar.gz".freeze
    CONTENT_TYPE = "application/gzip".freeze

    class ArchiveError < StandardError; end

    class << self
      # Unpack the conversation's stored session archive into `dir`.
      # No-op when the conversation has no archive yet (first turn).
      def restore(conversation, into:)
        return unless conversation.pi_session_archive.attached?

        conversation.pi_session_archive.open do |archive|
          extract(archive.path, into)
        end
      end

      # Tar `dir` and attach it to the conversation, replacing any prior
      # archive. No-op when `dir` is empty (pi wrote nothing).
      def store(conversation, from:)
        return unless Dir.exist?(from) && !Dir.empty?(from)

        Tempfile.create([ "pi-session", ".tar.gz" ]) do |tmp|
          compress(from, tmp.path)
          conversation.pi_session_archive.attach(
            io: File.open(tmp.path), filename: FILENAME, content_type: CONTENT_TYPE
          )
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
