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
end
