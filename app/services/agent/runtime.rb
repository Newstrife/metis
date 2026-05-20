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
  # v1 ships Runtime::Local — the agent as a local subprocess. Runtime::E2B
  # — the agent inside a secure microVM — is the planned isolated runtime.
  module Runtime
  end
end
