# See docs/projects.md.
class Project < ApplicationRecord
  NAME_MAX = 80

  validates :name, presence: true,
                    uniqueness: { scope: :team_id },
                    length: { maximum: NAME_MAX },
                    format: { without: /[\r\n]/, message: "can't contain line breaks" }

  belongs_to :team
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  has_many :conversations, dependent: :nullify

  scope :recent, -> { order(updated_at: :desc) }

  def ref_for(connector_type)
    external_refs[connector_type.to_s]
  end

  def github_repo       = ref_for("github")&.dig("repo").presence
  def linear_project_id = ref_for("linear")&.dig("project_id").presence
end
