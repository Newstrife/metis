class Conversation < ApplicationRecord
  belongs_to :user
  belongs_to :team
  has_many :messages, dependent: :destroy

  # The pi session directory, archived. Durable, worker-independent
  # storage for the agent's conversation memory (see Agent::SessionArchive).
  has_one_attached :pi_session_archive

  # A conversation is owned by a team; default it to the creator's
  # personal team unless one was given (docs/tenancy.md).
  before_validation :default_team, on: :create

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

  # Stamp a cancellation request for the in-flight turn. ChatJob polls
  # this mid-stream (compared against the turn's start) and aborts pi.
  def request_cancel!
    update_column(:cancel_requested_at, Time.current)
  end

  # Every file uploaded across the conversation, as Active Storage
  # attachments. Runtimes project these into pi's workspace each turn —
  # they are durable input, not archived session state (see
  # docs/session-persistence.md).
  def uploaded_files
    messages.with_attached_files.flat_map { |message| message.files.attachments }
  end

  private

  def default_team
    self.team ||= user&.personal_team
  end
end
