# A user's identity at an external OAuth provider (GitHub, Google, …).
# A user has many identities — one per provider they've signed in
# through or whose connector they've authorized. The `(provider, uid)`
# pair is the durable handle the omniauth callback looks up to find an
# existing user; email is fallback only. See docs/connectors.md.
class Identity < ApplicationRecord
  belongs_to :user

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
