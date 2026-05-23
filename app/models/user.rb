class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[github google_oauth2]

  has_many :memberships, dependent: :destroy
  has_many :teams, through: :memberships
  has_many :conversations, dependent: :destroy
  has_many :connector_credentials, dependent: :destroy
  has_many :identities, dependent: :destroy

  after_create :create_personal_team

  # The team-of-one created at signup — owner of this user's personal
  # resources (docs/tenancy.md).
  def personal_team
    teams.find_by(personal: true)
  end

  NOREPLY_EMAIL_SUFFIX = ".users.noreply.metis".freeze

  # Find or create a user from an OmniAuth callback. Always returns a
  # persisted User. Lookup is identity-first (`provider`+`uid`), then
  # falls back to email — so a password user gets the identity attached
  # rather than forked into a second account.
  def self.from_omniauth(auth)
    identity = Identity.find_by(provider: auth.provider, uid: auth.uid.to_s)
    if identity
      backfill_real_email(identity.user, auth)
      return identity.user
    end

    email = auth.info.email.presence || noreply_email(auth)
    user = find_or_initialize_by(email: email)
    user.password = Devise.friendly_token[0, 32] if user.new_record?
    user.save!
    user.identities.create!(provider: auth.provider, uid: auth.uid.to_s)
    user
  end

  # A stable synthetic address used when a provider's callback doesn't
  # include an email (e.g. a GitHub App without the "Email addresses"
  # permission). The user is still matched on subsequent sign-ins by
  # identity, not by email.
  def self.noreply_email(auth)
    handle = auth.info.nickname.presence || auth.info.name.presence || "user"
    "#{auth.uid}+#{handle.parameterize}@#{auth.provider}#{NOREPLY_EMAIL_SUFFIX}"
  end

  # An address we'd never have set if the user had given us a real
  # one — covers metis's own synth suffix and the noreply pseudo-emails
  # GitHub (and others) issue when the user keeps their address private.
  def self.placeholder_email?(email)
    email.to_s.include?("users.noreply.")
  end

  # Promote a placeholder noreply email to the real one when the
  # provider starts returning it (e.g. after a GitHub App gains the
  # "Email addresses" permission). Never the reverse — a sign-in
  # without auth.info.email, or with another placeholder, must not
  # overwrite a real email. Skipped if the real email is already taken
  # by another row; merging the two accounts is a separate concern.
  def self.backfill_real_email(user, auth)
    return unless auth.info.email.present?
    return if placeholder_email?(auth.info.email)
    return unless placeholder_email?(user.email)
    return if where.not(id: user.id).exists?(email: auth.info.email)

    user.update!(email: auth.info.email)
  end

  private

  # Every user gets a personal team (a team of one) at signup.
  def create_personal_team
    team = Team.create!(name: email, personal: true)
    memberships.create!(team: team, role: :owner)
  end
end
