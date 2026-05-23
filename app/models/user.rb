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

  # Find or create a user from an OmniAuth callback. Always returns a
  # persisted User. Lookup is identity-first (`provider`+`uid`), then
  # falls back to email — so a password user gets the identity attached
  # rather than forked into a second account.
  def self.from_omniauth(auth)
    identity = Identity.find_by(provider: auth.provider, uid: auth.uid.to_s)
    return identity.user if identity

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
    "#{auth.uid}+#{handle.parameterize}@#{auth.provider}.users.noreply.metis"
  end

  private

  # Every user gets a personal team (a team of one) at signup.
  def create_personal_team
    team = Team.create!(name: email, personal: true)
    memberships.create!(team: team, role: :owner)
  end
end
