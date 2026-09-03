# Grants one data directory to one role — a row in the role's
# permission list.
class DirectoryGrant < ApplicationRecord
  belongs_to :role
  belongs_to :data_directory

  validates :data_directory_id, uniqueness: { scope: :role_id }
end
