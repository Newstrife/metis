# A data-access role (RBAC): a named bundle of directory grants.
# Roles are freely creatable; `full_access` roles bypass directory
# checks entirely (operator/sysadmin). A user may hold many roles.
class Role < ApplicationRecord
  has_many :role_assignments, dependent: :destroy
  has_many :users, through: :role_assignments
  has_many :directory_grants, dependent: :destroy
  has_many :data_directories, through: :directory_grants

  validates :name, presence: true, uniqueness: true

  # Directories this role opens up. Full-access roles see everything —
  # callers should check `full_access?` first, this is the explicit list.
  def grants_all?
    full_access?
  end
end
