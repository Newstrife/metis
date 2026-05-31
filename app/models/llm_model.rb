# A model in the deployment's LLM catalog — pi's model id plus operator
# curation (enabled, label, ordering, and the single deployment default).
# Synced from pi by Agent::ModelCatalogSync; the `key` is passed to pi
# verbatim as --model. Deployment-level (see LlmProvider).
class LlmModel < ApplicationRecord
  validates :key, presence: true, uniqueness: { scope: :llm_provider_id }
  validates :label, presence: true

  belongs_to :llm_provider

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :key) }

  # The single enabled default for the deployment, or nil.
  def self.current_default
    enabled.find_by(is_default: true)
  end

  # Make this the deployment default, atomically clearing any other and
  # ensuring it's enabled (a disabled default would be unselectable).
  def make_default!
    transaction do
      LlmModel.where.not(id: id).where(is_default: true).update_all(is_default: false)
      update!(is_default: true, enabled: true)
    end
  end
end
