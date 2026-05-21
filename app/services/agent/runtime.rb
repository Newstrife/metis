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
  # Runtime::Local runs the agent as a local subprocess; Runtime::E2b runs
  # it inside a secure E2B microVM.
  module Runtime
    # Resolve the runtime for a conversation — a per-deployment choice
    # (config.x.agent.runtime).
    def self.for(conversation)
      build(conversation, Rails.application.config.x.agent.runtime)
    end

    def self.build(conversation, name)
      case name&.to_sym
      when :local then Local.new(conversation: conversation)
      when :e2b   then E2b.new(conversation: conversation)
      else
        raise Agent::Error, "Unknown agent runtime #{name.inspect} — set config.x.agent.runtime"
      end
    end
  end
end
