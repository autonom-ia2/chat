module Autonomia::Agents::TestState
  extend ActiveSupport::Concern

  included do
    after_update :invalidate_changed_test
  end

  RESPONSE_COLUMNS = %w[name instruction scaffold greeting fallback_message tone actuation handoff_rule mode agent_type].freeze
  RESPONSE_CONFIG_KEYS = (
    Autonomia::Agents::ConfigContract::PUBLIC_KEYS.excluding('faq_suggestions') +
    Autonomia::Agents::ConfigContract::OPERATIONAL_KEYS + %w[guardrails voice]
  ).freeze

  private

  def invalidate_changed_test
    return unless draft? && config.dig(Autonomia::Agents::AgentStateStore::NAMESPACE, 'test').present?

    reason = test_invalidation_reason
    invalidate_before_live_test(reason) if reason
  end

  def test_invalidation_reason
    return 'person' if saved_changes.keys.intersect?(RESPONSE_COLUMNS)

    old_config, new_config = saved_changes.fetch('config', [config, config]).map(&:to_h)
    return 'person' if old_config.slice(*RESPONSE_CONFIG_KEYS).compact != new_config.slice(*RESPONSE_CONFIG_KEYS).compact
    return 'material' if [false, 'false'].include?(old_config['with_knowledge']) != [false, 'false'].include?(new_config['with_knowledge'])

    nil
  end

  def invalidate_before_live_test(reason)
    return unless draft? && config.dig(Autonomia::Agents::AgentStateStore::NAMESPACE, 'test').present?

    Autonomia::Agents::AgentStateStore.invalidate!(agent: self, reason: reason)
  end
end
