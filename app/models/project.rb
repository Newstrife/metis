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

  # external_refs is keyed by connector type with per-connector field
  # names underneath, e.g. external_refs["github"]["repo"]. Callers
  # ask through the picker's REF_FIELD constant so adding a connector
  # doesn't need an accessor here.
  def ref_for(connector_type, field = nil)
    values = external_refs[connector_type.to_s]
    return values if field.nil?
    values&.dig(field.to_s).presence
  end
end
