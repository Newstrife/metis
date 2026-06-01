# A provider in the deployment's LLM catalog — pi's provider id plus the
# operator's curation (enabled, label, ordering). Deployment-level, not
# team-scoped: the same bend as provider API keys, which are also a
# deployment resource (VISION rule 4 / docs/tenancy.md). Synced from pi by
# Agent::ModelCatalogSync; surfaced in the composer by Agent::Catalog.
class LlmProvider < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :label, presence: true

  has_many :llm_models, dependent: :destroy

  scope :ordered, -> { order(:position, :key) }

  # A provider is enabled when any of its models is — it has no
  # independent enabled flag, so the page's provider toggle is just a
  # bulk enable/disable of the group (see #set_enabled!).
  def enabled?
    llm_models.any?(&:enabled?)
  end

  # Whether the deployment has an API key configured for this provider.
  # A provider can be enabled without a key, but its models won't run —
  # the page warns when that's the case.
  def api_key?
    Rails.application.config.x.agent.api_keys.to_h.key?(key)
  end

  # Bulk enable/disable every model under this provider — disabling hides
  # the whole group from the composer, enabling brings it back.
  def set_enabled!(value)
    llm_models.update_all(enabled: value, updated_at: Time.current)
  end
end
