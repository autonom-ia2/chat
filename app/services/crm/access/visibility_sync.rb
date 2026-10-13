# Quando o card muda de funil, de status ou de conversa, ou nasce (#1148, parte C), muda quem vê a conversa. Só a visão
# de quem tem linha restritiva na caixa depende do card (membro sem restrição e administrador veem como antes e não
# recebem nada daqui): dessas pessoas, quem vê agora recebe a conversa (conversation.updated; para quem já via, só
# atualiza) e quem deixou de ver a tira da lista (conversation.access_revoked). Conversa aberta e sem atendente vai para
# quem cuida do funil do card (Crm::Entrega, #1454). Conta sem acesso configurado: nada acontece.
module Crm::Access::VisibilitySync
  REVOKED = 'conversation.access_revoked'.freeze

  module_function

  def perform(conversation)
    return if conversation.nil?
    return unless Crm::Access::AccountFlag.any?(conversation.account_id)

    # Saída da triagem e participantes (#1150): antes de decidir quem vê, porque pode tirar o atendente.
    Crm::Access::TriageExit.new(conversation).perform
    conversation.reload

    recipients = Crm::Access::Recipients.new(conversation)
    restricted = recipients.restricted_user_ids
    return if restricted.empty?

    blocked = recipients.blocked_user_ids
    visible_tokens = conversation.inbox.members.where(id: restricted - blocked).pluck(:pubsub_token)
    broadcast(conversation, visible_tokens, Events::Types::CONVERSATION_UPDATED) { conversation.push_event_data }
    broadcast(conversation, User.where(id: blocked).pluck(:pubsub_token), REVOKED) { { id: conversation.id } }
    reassign(conversation)
  end

  def broadcast(conversation, tokens, event)
    tokens = tokens.compact.uniq
    return if tokens.empty?

    ActionCableBroadcastJob.perform_later(tokens, event, yield.merge(account_id: conversation.account_id))
  end

  # A conversa sem atendente que ganhou funil vai para quem cuida dele (decisão de 11/10: o card nasce depois da
  # conversa), pelo motor de entrega (#1454), com ou sem o rodízio nativo da caixa. Só chega aqui caixa com pessoa
  # restrita (linha de administrador não restringe nada, como nenhuma linha): nas outras o funil do card não muda quem
  # pode receber (revisão da parte C). Robô atendendo sem ter passado a conversa continua com ela; a que o motor já
  # segura fica com a fila dele (HandoffDrainJob).
  def reassign(conversation)
    return unless conversation.open? && conversation.awaiting_person?
    return if conversation.crm_delivery_pending?

    Crm::Entrega.new(conversation: conversation, motivo: 'triagem', origem: 'visibilidade').call
  end
end
