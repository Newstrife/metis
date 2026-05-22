# Joins a user to a team with a role — the authorization primitive
# (docs/tenancy.md). A user may touch a resource when
# `resource.team.members.include?(user)`.
class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :team

  enum :role, { member: 0, admin: 1, owner: 2 }

  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :team_id }
end
