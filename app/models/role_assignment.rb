# Joins a user to a data-access role. A user may hold many roles;
# effective permissions are the union of all their roles' grants.
class RoleAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :role

  validates :role_id, uniqueness: { scope: :user_id }
end
