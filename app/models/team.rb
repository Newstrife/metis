# A team — the single tenancy unit (docs/tenancy.md). Every ownable
# resource belongs to a team. A personal account is a team of one,
# created for each user at signup.
class Team < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :members, through: :memberships, source: :user
  has_many :conversations, dependent: :destroy
  has_many :connectors, dependent: :destroy

  validates :name, presence: true
end
