module Agent
  module Runtime
    # Runs pi as a local subprocess in a per-conversation scratch
    # workspace, restoring and persisting that workspace via Active
    # Storage around each run.
    #
    # NOT an isolation boundary: pi has shell access and `bash` escapes
    # the workspace directory. Runtime::Local is for single-operator,
    # trusted use (development). Runtime::E2B — pi inside a secure
    # microVM — is the isolated runtime for multi-tenant exposure.
    class Local < Base
      def session_dir
        workspace.session_dir
      end

      def run(pi_args:, files: [])
        workspace.prepare!
        Agent::SessionArchive.restore(conversation, into: workspace.scope_dir)
        stage_files(files)
        session = PiAgent.session(args: pi_args, cwd: workspace.workspace_dir.to_s)
        begin
          yield session
        ensure
          session.close
          persist
        end
      end

      private

      def workspace
        @workspace ||= Agent::Workspace.for(conversation)
      end

      # Write uploaded files into pi's working directory. Filenames are
      # basenamed so a crafted name cannot escape the workspace; the
      # files are then archived with the scope, so they persist for
      # later turns (and pi can edit them).
      def stage_files(files)
        files.each do |file|
          name = File.basename(file.filename.to_s)
          next if name.blank? || [ ".", ".." ].include?(name)

          file.open { |io| IO.copy_stream(io, workspace.workspace_dir.join(name)) }
        end
      end

      # Capture the scratch scope back to durable storage. A persistence
      # failure is logged, never raised — it must not crash the turn the
      # user just saw stream.
      def persist
        Agent::SessionArchive.store(conversation, from: workspace.scope_dir)
      rescue StandardError => e
        Rails.logger.error("Runtime::Local archive failed for conversation #{conversation.id}: #{e.message}")
      end
    end
  end
end
