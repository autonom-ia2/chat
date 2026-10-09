module Autonomia::Agents::ActivationContract
  private

  def validate_activation_instruction
    return unless target_operating?
    return if activation_instruction.present?

    render_unprocessable(
      I18n.t('autonomia.agents.errors.missing_instruction', locale: current_account.locale),
      code: 'missing_instruction'
    )
  end

  def requested_manual_mode?
    params.dig(:agent, :mode).to_s == 'manual'
  end

  def target_operating?
    target_status == 'active' && target_enabled
  end

  def target_status
    raw = params.dig(:agent, :status)
    raw.present? ? raw.to_s : @agent&.status.to_s
  end

  def target_enabled
    raw = params.dig(:agent, :enabled)
    return @agent.enabled? if raw.nil? && @agent

    ActiveModel::Type::Boolean.new.cast(raw)
  end

  def activation_instruction
    raw_agent = params[:agent]
    return requested_instruction(raw_agent) if requested_agent_mode(raw_agent) == 'manual'

    @agent&.instrucao_do_sistema.to_s
  end

  def requested_agent_mode(raw_agent)
    return unless raw_agent.respond_to?(:key?)

    (raw_agent[:mode] || raw_agent['mode']).presence.to_s
  end

  def requested_instruction(raw_agent)
    return '' unless raw_agent.respond_to?(:key?)
    return '' unless raw_agent.key?(:instruction) || raw_agent.key?('instruction')

    (raw_agent[:instruction] || raw_agent['instruction']).to_s
  end
end
