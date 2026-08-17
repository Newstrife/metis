# Deployment-level feature switches, editable at runtime from
# /settings/features (superuser-only). Each entry in MODULES is one card on
# that page — adding a module is one registry line plus its locale copy.
#
# Reads go through a short-TTL cache so a toggle flip reaches the web and
# bin/jobs processes within seconds without a per-turn DB hit.
class Setting < ApplicationRecord
  self.primary_key = "key"

  MODULES = {
    "wecom.auto_provision" => {
      type: :boolean, default: true, i18n: "wecom_auto_provision"
    },
    "wecom.group_conversations" => {
      type: :boolean, default: true, i18n: "wecom_group_conversations"
    },
    "wecom.group_whitelist" => {
      type: :list, default: [], i18n: "wecom_group_whitelist"
    },
    "security.approval_push" => {
      type: :boolean, default: true, i18n: "security_approval_push"
    },
    "security.trust_guard" => {
      type: :boolean, default: true, i18n: "security_trust_guard"
    }
  }.freeze

  TTL = 5.seconds

  def self.get(key)
    mod = MODULES.fetch(key)
    stored = Rails.cache.fetch("setting:#{key}", expires_in: TTL) do
      find_by(key: key)&.value
    end
    stored.nil? ? mod[:default] : stored
  end

  def self.set(key, raw)
    mod = MODULES.fetch(key)
    value = cast(mod[:type], raw)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
    Rails.cache.delete("setting:#{key}")
    value
  end

  def self.cast(type, raw)
    case type
    when :boolean then raw == true || raw == "true"
    when :list then Array(raw).map { |item| item.to_s.strip }.reject(&:blank?).uniq
    else raw
    end
  end
end
