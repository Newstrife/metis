class ApiKey < ApplicationRecord
  belongs_to :user

  encrypts :key

  validates :provider, presence: true, uniqueness: { scope: :user_id }
  validates :key, presence: true
end
