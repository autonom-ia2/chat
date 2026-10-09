module Autonomia::Agents::BuilderAttributes
  private

  # D22 reads the instruction reloaded under the Agent lock, not the Builder snapshot.
  def builder_attributes_for_current_instruction(attrs)
    return attrs if instruction.blank?

    allowed = attrs.slice(:instruction, :scaffold, :human_card, :handoff_rule)
    allowed[:config] = attrs.fetch(:config).slice('guardrails') if attrs.key?(:config)
    allowed
  end

  def apply_builder_attributes!(attrs)
    return false if deleted?

    merged = attrs.dup
    merged[:config] = config.to_h.merge(attrs[:config] || {}) if attrs.key?(:config)
    update!(merged)
    true
  end
end
