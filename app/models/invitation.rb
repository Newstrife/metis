# A pending offer to join a team, accepted via a tokenized link
# (docs/tenancy.md). Owners are never invited — ownership transfer is
# its own flow — so only member/admin are invitable.
class Invitation < ApplicationRecord
  INVITABLE_ROLES = %w[member admin].freeze
  EXPIRES_IN = 14.days

  belongs_to :team
  belongs_to :invited_by, class_name: "User"

  enum :role, { member: 0, admin: 1, owner: 2 }

  scope :pending, -> { where(accepted_at: nil) }

  before_validation :normalize_email
  before_validation :set_defaults, on: :create

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: INVITABLE_ROLES }
  validates :token, presence: true, uniqueness: true
  validates :email, uniqueness: { scope: :team_id, conditions: -> { pending },
                                  message: "already has a pending invitation" }
  validate :email_not_already_member, on: :create

  def expired?
    expires_at.past?
  end

  # Idempotent: re-accepting (or accepting when already a member) just
  # stamps accepted_at; an existing membership keeps its role.
  def accept!(user)
    transaction do
      team.memberships.find_or_create_by!(user: user) { |m| m.role = role }
      update!(accepted_at: Time.current)
    end
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def set_defaults
    self.token ||= SecureRandom.urlsafe_base64(24)
    self.expires_at ||= EXPIRES_IN.from_now
  end

  def email_not_already_member
    return if team.nil? || email.blank?
    return unless team.members.exists?(email: email)

    errors.add(:email, "is already a member of this team")
  end
end
