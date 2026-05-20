# The Agent service layer drives coding-agent backends and translates
# their native event streams into a canonical UI vocabulary (UiEvent).
#
# v1 ships the :pi backend; :claude_code and :codex are planned.
module Agent
  class Error < StandardError; end

  # Raised when a conversation's backend has no adapter yet.
  class UnsupportedBackendError < Error; end
end
