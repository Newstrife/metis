class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[github]

  has_many :memberships, dependent: :destroy
  has_many :teams, through: :memberships
  has_many :conversations, dependent: :destroy
  has_many :connector_credentials, dependent: :destroy

  after_create :create_personal_team

  # The team-of-one created at signup — owner of this user's personal
  # resources (docs/tenancy.md).
  def personal_team
    teams.find_by(personal: true)
  end

  # Find or create a user from a GitHub OmniAuth callback. Always
  # returns a persisted User. If a password user already exists at the
  # same email, the GitHub identity is attached to it instead of
  # forking a separate account.
  def self.from_github_omniauth(auth)
    existing = find_by(provider: "github", uid: auth.uid.to_s)
    return existing if existing

    email = auth.info.email.presence || github_noreply_email(auth)
    user = find_or_initialize_by(email: email)
    user.password = Devise.friendly_token[0, 32] if user.new_record?
    user.assign_attributes(provider: "github", uid: auth.uid.to_s)
    user.save!
    user
  end

  # GitHub's stable, per-user noreply address — used when the App was
  # not granted the "Email addresses" permission and `auth.info.email`
  # is nil, so a new user can still be created (and matched on later
  # logins by uid, not email).
  def self.github_noreply_email(auth)
    login = auth.info.nickname.presence || "user"
    "#{auth.uid}+#{login}@users.noreply.github.com"
  end

  private

  # Every user gets a personal team (a team of one) at signup.
  def create_personal_team
    team = Team.create!(name: email, personal: true)
    memberships.create!(team: team, role: :owner)
  end
end
