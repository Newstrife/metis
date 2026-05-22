class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :memberships, dependent: :destroy
  has_many :teams, through: :memberships
  has_many :conversations, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :connector_credentials, dependent: :destroy

  after_create :create_personal_team

  def api_key_for(provider)
    api_keys.find_by(provider: provider.to_s)&.key
  end

  # The team-of-one created at signup — owner of this user's personal
  # resources (docs/tenancy.md).
  def personal_team
    teams.find_by(personal: true)
  end

  private

  # Every user gets a personal team (a team of one) at signup.
  def create_personal_team
    team = Team.create!(name: email, personal: true)
    memberships.create!(team: team, role: :owner)
  end
end
