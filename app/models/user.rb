class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[github google_oauth2]

  has_many :memberships, dependent: :destroy
  has_many :teams, through: :memberships
  has_many :conversations, dependent: :destroy
  has_many :connector_credentials, dependent: :destroy
  has_many :identities, dependent: :destroy
  has_many :oauth_grants, dependent: :destroy

  after_create :create_personal_team

  # The team-of-one created at signup — owner of this user's personal
  # resources (docs/tenancy.md).
  def personal_team
    teams.find_by(personal: true)
  end

  NOREPLY_EMAIL_SUFFIX = ".users.noreply.metis".freeze

  # Addresses we'd never have set if the user had given us a real one.
  # Anchored, not substring — `alex@users.noreply.corp.com` (a real GHE
  # noreply domain) is a real email and must not be rewritten.
  #
  # - metis's own synth (User.noreply_email): `<uid>+<handle>@<provider>.users.noreply.metis`
  # - GitHub's private-email pseudo-address: `<id>+<login>@users.noreply.github.com`
  PLACEHOLDER_EMAIL_PATTERNS = [
    /\.users\.noreply\.metis\z/,
    /\A\d+\+[^@]+@users\.noreply\.github\.com\z/
  ].freeze

  # Find or create a user from an OmniAuth callback. Always returns a
  # persisted User. Lookup is identity-first (`provider`+`uid`), then
  # falls back to email — so a password user gets the identity attached
  # rather than forked into a second account.
  #
  # The create-new-user path is wrapped in a transaction so the
  # concurrent-first-sign-in race (two callbacks for the same
  # provider+uid both passing Identity.find_by) doesn't leave an
  # orphan User + Team + Membership for the losing callback. On
  # collision the transaction rolls back and we retry once — the
  # second pass finds the winner's Identity at the top of the method.
  def self.from_omniauth(auth)
    attempts = 0
    begin
      identity = Identity.find_by(provider: auth.provider, uid: auth.uid.to_s)
      if identity
        backfill_real_email(identity.user, auth)
        return identity.user
      end

      transaction do
        email = auth.info.email.presence || noreply_email(auth)
        user = find_or_initialize_by(email: email)
        user.password = Devise.friendly_token[0, 32] if user.new_record?
        user.save!
        user.identities.create!(provider: auth.provider, uid: auth.uid.to_s)
        user
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts == 1 && Identity.exists?(provider: auth.provider, uid: auth.uid.to_s)
      raise
    end
  end

  # A stable synthetic address used when a provider's callback doesn't
  # include an email (e.g. a GitHub App without the "Email addresses"
  # permission). The user is still matched on subsequent sign-ins by
  # identity, not by email.
  def self.noreply_email(auth)
    handle = auth.info.nickname.presence || auth.info.name.presence || "user"
    "#{auth.uid}+#{handle.parameterize}@#{auth.provider}#{NOREPLY_EMAIL_SUFFIX}"
  end

  def self.placeholder_email?(email)
    s = email.to_s
    PLACEHOLDER_EMAIL_PATTERNS.any? { |re| s.match?(re) }
  end

  # Promote a placeholder noreply email to the real one when the
  # provider starts returning it (e.g. after a GitHub App gains the
  # "Email addresses" permission). Never the reverse — a sign-in
  # without auth.info.email, or with another placeholder, must not
  # overwrite a real email. Best-effort: a failed backfill (TOCTOU
  # collision, provider returned a Devise-invalid address) logs and
  # returns rather than crashing the sign-in.
  def self.backfill_real_email(user, auth)
    return unless auth.info.email.present?
    return if placeholder_email?(auth.info.email)
    return unless placeholder_email?(user.email)
    return if where.not(id: user.id).exists?(email: auth.info.email)

    user.update!(email: auth.info.email)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    Rails.logger.warn(
      "User#backfill_real_email skipped for user #{user.id}: #{error.class}: #{error.message}"
    )
  end

  private

  # Every user gets a personal team (a team of one) at signup.
  def create_personal_team
    team = Team.create!(name: email, personal: true)
    memberships.create!(team: team, role: :owner)
  end
end
