class Crm::StageAutomations::StepConfigValidator
  def initialize(step)
    @step = step
  end

  def validate
    case @step.action_type
    when 'create_follow_up'
      validate_create_follow_up!
    when 'assign_owner'
      validate_assign_owner!
    when 'move_stage'
      validate_move_stage!
    when 'perguntar_ao_decisor'
      validate_perguntar_ao_decisor!
    end
  end

  private

  def config
    (@step.action_config || {}).to_h.stringify_keys
  end

  def validate_create_follow_up!
    return if config['title'].to_s.strip.present?

    @step.errors.add(:action_config, 'title is required for create_follow_up steps')
  end

  def validate_assign_owner!
    return if config['owner_id'].present? || ActiveModel::Type::Boolean.new.cast(config['use_card_owner'])

    @step.errors.add(:action_config, 'owner_id or use_card_owner is required for assign_owner steps')
  end

  def validate_move_stage!
    return if config['target_stage_id'].present?

    @step.errors.add(:action_config, 'target_stage_id is required for move_stage steps')
  end

  # O mesmo contrato do passo da regra de automação (#858): o Decisor tem de ser da conta, a chave uma das
  # respostas dele e o que ele lê, algo que um card tem. Conferência por igualdade; a recusa ensina o certo.
  def validate_perguntar_ao_decisor!
    decisor = Autonomia::Decisor.find_by(id: config['decisor_id'].to_s, account_id: @step.account_id)
    if decisor.blank?
      return @step.errors.add(:action_config, 'decisor_id must be a Decisor of this account (action_config: { decisor_id, chave_que_segue })')
    end

    recusa = decisor.recusa_de_gatilho('etapa')
    return @step.errors.add(:action_config, recusa) if recusa
    return if decisor.resposta?(config['chave_que_segue'])

    @step.errors.add(:action_config, "chave_que_segue must be one of: #{decisor.chaves.join(', ')}")
  end
end
