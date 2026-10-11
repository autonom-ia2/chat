# Quem, entre os membros da caixa, pode ver a conversa pelo acesso por funil (#1148, parte B): tempo real, notificações,
# contadores e rodízio usam isto para não entregar a conversa a quem a lista e o link já escondem
# (Crm::Access::ConversationScope, parte A).
#
# Sem linha de acesso restritiva na caixa (o caso de todo mundo hoje), uma consulta só e nada muda. Com restrição, os
# dados da conversa são lidos uma vez (atendente, participantes, funis dos cards) e cada pessoa restrita é avaliada em
# memória pela mesma regra do link (ConversationScope.visible_by_facts?): o custo não cresce por pessoa, e isto roda
# dentro do envio de cada mensagem.
class Crm::Access::Recipients
  # Membros da caixa que podem ver a conversa: o tempo real e as notificações não entregam o que a lista esconde.
  def self.inbox_members(conversation)
    new(conversation).filter(conversation.inbox.members)
  end

  def initialize(conversation)
    @conversation = conversation
  end

  # Os usuários (relação ou lista) sem os que o funil esconde.
  def filter(users)
    blocked = blocked_user_ids
    return users if blocked.empty?
    return users.where.not(id: blocked) if users.respond_to?(:where)

    users.reject { |user| blocked.include?(user.id) }
  end

  # Rodízio: membros da caixa (InboxMember) que podem receber a conversa.
  def filter_members(inbox_members)
    blocked = blocked_user_ids
    blocked.empty? ? inbox_members : inbox_members.where.not(user_id: blocked)
  end

  def blocked_user_ids
    @blocked_user_ids ||= begin
      accesses = restricted_accesses
      accesses.empty? ? [] : blocked_among(accesses)
    end
  end

  private

  def restricted_accesses
    Crm::InboxAgentAccess.where(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id)
                         .includes(:agent_pipelines).select(&:restricts?)
  end

  # Administrador vê tudo, mesmo com linha (como no ConversationScope).
  def blocked_among(accesses)
    admins = AccountUser.where(account_id: @conversation.account_id, user_id: accesses.map(&:user_id))
                        .administrator.pluck(:user_id)
    facts = conversation_facts
    accesses.reject { |access| admins.include?(access.user_id) }
            .reject { |access| Crm::Access::ConversationScope.visible_by_facts?(access, access.user_id, facts) }
            .map(&:user_id)
  end

  def conversation_facts
    {
      assignee_id: @conversation.assignee_id,
      participant_ids: ConversationParticipant.where(conversation_id: @conversation.id).pluck(:user_id),
      card_pipeline_ids: card_pipeline_ids
    }
  end

  # Funis dos cards que prendem a conversa: a principal de cada card ou um vínculo em crm_card_conversations.
  def card_pipeline_ids
    linked = Crm::CardConversation.where(account_id: @conversation.account_id, conversation_id: @conversation.id).select(:card_id)
    cards = Crm::Card.where(account_id: @conversation.account_id)
                     .where.not(status: Crm::Access::ConversationScope::RELEASED)
    cards.where(conversation_id: @conversation.id).or(cards.where(id: linked)).distinct.pluck(:pipeline_id)
  end
end
