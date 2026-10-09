module Autonomia::Agents::InstructionContract
  private

  def validate_manual_instruction
    raw = params[:agent]
    return unless manual_mode_request?(raw)
    return if exempt_manual_instruction?(raw)

    render_unprocessable(
      I18n.t('autonomia.agents.errors.manual_instruction_required', locale: current_account.locale),
      code: 'manual_instruction_required', key: 'instruction'
    )
  end

  def manual_mode_request?(raw)
    return false unless raw.respond_to?(:key?)
    return false unless raw.key?(:mode) || raw.key?('mode')

    (raw[:mode] || raw['mode']).to_s == 'manual'
  end

  def exempt_manual_instruction?(raw)
    return true if @agent&.manual? && !instruction_present?(raw)

    value = instruction_value(raw)
    value.is_a?(String) && value.strip.present?
  end

  def restore_guided_mode_if_requested!
    return unless @agent.manual? && params.dig(:agent, :mode).to_s == 'guided'

    version = @agent.latest_guided_instruction_version
    raise ::Autonomia::Agents::Errors::NoGuidedVersion if version.blank?

    @agent.restore_instruction!(version, created_by: Current.user)
    @agent.reload
  end

  def requested_internal_actuation?
    raw = params[:agent]
    return @agent.actuation_internal? unless raw.respond_to?(:key?)

    has_actuation = raw.key?(:actuation) || raw.key?('actuation')
    return @agent.actuation_internal? unless has_actuation

    (raw[:actuation] || raw['actuation']).to_s == 'internal'
  end

  def record_manual_instruction_version(instruction_before)
    return unless @agent.manual? && @agent.instruction.to_s != instruction_before.to_s

    @agent.record_instruction_version!(reason: 'manual_edit', created_by: Current.user)
  rescue StandardError => e
    Rails.logger.error("[autonomia][agents] manual instruction version record failed agent=#{@agent.id}: #{e.class.name}")
  end

  def record_guided_version_before_manual_switch
    return unless requested_manual_mode? && @agent.guided? && @agent.instruction.present?

    @agent.record_instruction_version!(reason: 'before_manual', created_by: Current.user, force: true)
  end

  # Andaime mínimo aplicado pelo backend em modo manual (IP oculto); embrulha a instrução do usuário
  # com guardrails de segurança/formato/handoff. Nunca vem dos params nem é exposto.
  def apply_manual_scaffold
    @agent.scaffold = ::Autonomia::Agents::Agent::MANUAL_SCAFFOLD if @agent.manual?
  end

  def rejeitar_edicao_da_instrucao_mantida
    agente = params[:agent]
    return unless agente.respond_to?(:key?)

    raise ::Autonomia::Agents::Agent::InstrucaoMantida if @agent.instrucao_mantida? && edita_o_que_e_mantido?(agente)
    return if @agent.instrucao_mantida? || !pede_o_tipo_mantido?(agente)

    raise ::Autonomia::Agents::Agent::InstrucaoMantida
  end

  def edita_o_que_e_mantido?(agente)
    modo = agente[:mode].to_s
    agente.key?(:instruction) || (modo.present? && modo != 'guided') || troca_o_tipo?(agente)
  end

  def troca_o_tipo?(agente)
    agente.key?(:agent_type) && agente[:agent_type].to_s != @agent.agent_type
  end

  def pede_o_tipo_mantido?(agente)
    agente.key?(:agent_type) && instrucao_mantida_pelo_tipo?(agente[:agent_type])
  end

  def instrucao_mantida_pelo_tipo?(agent_type)
    ::Autonomia::Agents::Agent.new(agent_type: agent_type.to_s).instrucao_mantida?
  end

  def discard_generated_instruction_on_manual_switch
    requested = params.dig(:agent, :mode).to_s
    @agent.instruction = nil if requested == 'manual' && @agent.guided?
  end

  def update_agent_attributes
    attrs = agent_params
    voice_supplied = attrs.key?(:voice)
    voice = attrs.delete(:voice)
    update_quote_name!(attrs.delete(:name)) if @agent.instrucao_mantida? && attrs.key?(:name)
    @agent.assign_attributes(attrs.except(:config))
    merge_config!(attrs[:config]) if attrs.key?(:config)
    apply_voice_config(voice) if voice_supplied
  end

  def instruction_present?(raw)
    raw.key?(:instruction) || raw.key?('instruction')
  end

  def instruction_value(raw)
    raw.key?(:instruction) ? raw[:instruction] : raw['instruction']
  end
end
