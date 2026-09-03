# One permission unit of the knowledge base: a subdirectory under the
# knowledge root (e.g. E:\enterprise_data\考勤制度). Directories are
# freely registrable — create the folder on disk, then register it here
# so it can be granted to roles. `public_access` directories are visible
# to every user without an explicit grant.
class DataDirectory < ApplicationRecord
  has_many :directory_grants, dependent: :destroy
  has_many :roles, through: :directory_grants

  validates :name, presence: true
  validates :path, presence: true, uniqueness: true
  validate :path_is_relative_and_contained

  private

  # Paths are relative to the knowledge root — absolute paths and
  # parent-traversal would escape the permission boundary.
  def path_is_relative_and_contained
    return if path.blank?

    p = path.tr("\\", "/")
    if p.start_with?("/") || p.match?(/\A[a-z]:/i) || p.split("/").include?("..")
      errors.add(:path, :invalid)
    end
  end
end
