# Ações de Automação sobre o card do CRM da conversa. Usam os mesmos serviços da ação manual no
# Kanban, então mover, ganhar ou perder também disparam as automações de etapa e os eventos de
# conversão (Meta CAPI / Google) configurados no funil.
module AutomationRules::CrmActions
  include Events::Types

  private

  # Só cria quando a conversa não tem card aberto: com só cards ganhos/perdidos, pedido novo vira card novo (#1197).
  # Sem o índice único (#1142), duas automações disparadas juntas poderiam criar dois: a trava da conversa e a
  # checagem dentro dela garantem um só.
  def crm_create_card(params)
    return unless Crm::Config.enabled?

    stage = crm_stage(params)
    return if stage.blank?

    card = nil
    @conversation.with_lock do
      next if crm_card&.open?

      card = Crm::Cards::Creator.new(
        account: @account, user: nil, conversation: @conversation,
        params: { pipeline_id: stage.pipeline_id, stage_id: stage.id }
      ).perform
    end
    Crm::Cards::Broadcaster.broadcast(card, CRM_CARD_CREATED) if card.present?
  end

  def crm_move_card_stage(params)
    stage = crm_stage(params)
    card = crm_card_for_pipeline(stage&.pipeline_id)
    # Como no Kanban (só cards abertos): mover card ganho/perdido reabriria eventos de etapa.
    return if card.blank? || stage.blank? || !card.open?

    Crm::Cards::Mover.new(card: card, actor: nil, target_stage: stage).perform
    Crm::Cards::Broadcaster.broadcast(card, CRM_CARD_MOVED)
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
    Crm::Cards::Broadcaster.broadcast(card, CRM_CARD_UPDATED)
  end

  def close_crm_card(result)
    card = crm_card
    return if card.blank? || card.status == Crm::Cards::Outcome.status_for(card.pipeline, result)

    Crm::Cards::Closer.new(card: card, actor: nil, result: result).perform
    Crm::Cards::Broadcaster.broadcast(card, CRM_CARD_UPDATED)
  end

  def crm_card
    return unless Crm::Config.enabled?

    Crm::Cards::ConversationCardFinder.new(account: @account).find(@conversation)
  end

  # Mover para uma etapa (#1141): com vários cards na conversa, move o card aberto do funil daquela etapa (o assunto
  # atual primeiro); sem card aberto nesse funil, o assunto atual — que é o que a ação sempre moveu, inclusive entre funis.
  def crm_card_for_pipeline(pipeline_id)
    return unless Crm::Config.enabled?

    cards = Crm::Cards::ConversationCardFinder.new(account: @account).all(@conversation).to_a
    cards.find { |card| card.open? && card.pipeline_id == pipeline_id } || cards.first
  end

  def crm_stage(params)
    Crm::PipelineStage.find_by(id: Array(params).first, account_id: @account.id)
  end
end
