class Conversation < ApplicationRecord
  # v1 ships :pi only; :claude_code and :codex are wired for the
  # multi-backend future (see plans/web-agent-stack.md).
  enum :backend, { pi: 0, claude_code: 1, codex: 2 }

  belongs_to :user
  has_many :messages, dependent: :destroy

  # The pi session directory, archived. Durable, worker-independent
  # storage for the agent's conversation memory (see Agent::SessionArchive).
  has_one_attached :pi_session_archive

  scope :recent, -> { order(updated_at: :desc) }

  def display_title
    title.presence || "Untitled conversation"
  end

  # The model in use, preferring the one pi actually resolved (captured
  # in agent_model after a turn) over the choice made at creation
  # (settings). nil before either is known.
  def model_label
    agent_model["name"].presence || settings["model"].presence
  end

  # The runtime the last turn ran on (local, e2b), or nil before any.
  def runtime_label
    runtime_state["runtime"].presence
  end

  # True while a turn is running — an assistant message is still pending
  # or streaming. Used to refuse a second concurrent turn.
  def turn_in_progress?
    messages.where(role: :assistant, streaming_status: %i[pending streaming]).exists?
  end
end
