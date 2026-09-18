# Ações de Automação sobre o card do CRM da conversa. Usam os mesmos serviços da ação manual no
# Kanban, então mover, ganhar ou perder também disparam as automações de etapa e os eventos de
# conversão (Meta CAPI / Google) configurados no funil.
module AutomationRules::CrmActions
  private

  def crm_create_card(params)
    return unless Crm::Config.enabled?
    return if crm_card.present?

    stage = crm_stage(params)
    return if stage.blank?

    Crm::Cards::Creator.new(
      account: @account, user: nil, conversation: @conversation,
      params: { pipeline_id: stage.pipeline_id, stage_id: stage.id }
    ).perform
  end

  def crm_move_card_stage(params)
    card = crm_card
    stage = crm_stage(params)
    return if card.blank? || stage.blank?

    Crm::Cards::Mover.new(card: card, actor: nil, target_stage: stage).perform
  end

  def crm_mark_card_won(_params)
    close_crm_card('won')
  end

  def crm_mark_card_lost(_params)
    close_crm_card('lost')
  end

  def crm_assign_card_owner(params)
    card = crm_card
    owner = @account.users.find_by(id: Array(params).first)
    return if card.blank? || owner.blank? || card.owner_id == owner.id

    card.update!(owner: owner, last_activity_at: Time.current)
    Crm::ActivityLogger.new(card: card, actor: nil, event_type: 'update', payload: { owner_id: owner.id }).perform
  end

  def close_crm_card(result)
    card = crm_card
    return if card.blank? || card.status == result

    Crm::Cards::Closer.new(card: card, actor: nil, result: result).perform
  end

  def crm_card
    return unless Crm::Config.enabled?

    Crm::Cards::ConversationCardFinder.new(account: @account).find(@conversation)
  end

  def crm_stage(params)
    Crm::PipelineStage.find_by(id: Array(params).first, account_id: @account.id)
  end
end
