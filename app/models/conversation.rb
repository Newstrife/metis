class Conversation < ApplicationRecord
  # v1 ships :pi only; :claude_code and :codex are wired for the
  # multi-backend future (see plans/web-agent-stack.md).
  enum :backend, { pi: 0, claude_code: 1, codex: 2 }

  belongs_to :user
  has_many :messages, dependent: :destroy

  scope :recent, -> { order(updated_at: :desc) }

  def display_title
    title.presence || "Untitled conversation"
  end
end
