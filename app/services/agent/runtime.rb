module Agent
  # A Runtime is *where* a coding agent runs — the second axis of
  # composition alongside the agent itself (Agent::Adapters). It owns the
  # agent's filesystem (session + workspace directories), the lifecycle
  # bracket around a run (provision -> yield a live session -> finalize),
  # and, for remote runtimes, the transport that carries the agent's RPC.
  #
  # Contract (see Runtime::Base):
  #   #session_dir              -> path for the agent's --session-dir
  #   #run(pi_args:) { |sess| } -> provision, open a PiAgent::Session,
  #                                yield it, finalize (persist + tear down)
  #
  # Runtime::Local runs the agent as a local subprocess; Runtime::Docker
  # runs it in a Docker container; Runtime::E2b runs it inside a secure
  # E2B microVM.
  module Runtime
    # Resolve the runtime for a conversation — a per-deployment choice
    # (config.x.agent.runtime).
    def self.for(conversation)
      build(conversation, Rails.application.config.x.agent.runtime)
    end

    def self.build(conversation, name)
      case name&.to_sym
      when :local  then Local.new(conversation: conversation)
      when :docker then Docker.new(conversation: conversation)
      when :e2b    then E2b.new(conversation: conversation)
      else
        raise Agent::Error, "Unknown agent runtime #{name.inspect} — set config.x.agent.runtime"
      end
    end

    # The pi extensions shipped with the app, version-controlled under
    # .pi/extensions/ (one self-contained <name>/index.ts each). pi runs
    # in a scratch workspace, so they are not on its discovery path: each
    # runtime makes them reachable from pi's execution environment and the
    # Pi adapter loads them explicitly with `pi --extension`.
    def self.extension_sources
      Dir.glob(Rails.root.join(".pi/extensions/*/index.ts")).sort.map { |path| Pathname.new(path) }
    end
  end
end
