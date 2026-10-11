# O funil do card libera a visão da conversa (multifunil 8/11, #1148, R2–R5). Um lugar só para a regra: lista de
# conversas, link, busca, tempo real, notificações, contadores e CRM leem daqui.
#
# Por pessoa e por caixa (Crm::InboxAgentAccess). Sem linha, ou linha que libera tudo, nada muda: vale a regra de caixa
# de sempre (R5). Com restrição, numa caixa a pessoa vê a conversa quando:
# - está atribuída a ela ou ela participa (atribuído e participante sempre veem, decisão do Rodrigo em 11/10);
# - senão, se não é "Só as suas": algum card da conversa está num funil dela, ou a conversa não tem card e ela tem a
#   triagem (R3).
# Administrador vê tudo. Card arquivado não conta como card, como no ConversationCardFinder.
#
# Este filtro só RESTRINGE: quem chama já aplicou a regra de caixa (membro da caixa, time, função personalizada).
class Crm::Access::ConversationScope
  ARCHIVED = Crm::Card.statuses[:archived]

  def initialize(user:, account:)
    @user = user
    @account = account
  end

  # As conversas da relação que a pessoa pode ver.
  def apply(relation)
    return relation if restrictions.empty?

    free = relation.where.not(conversations: { inbox_id: restrictions.map(&:inbox_id) })
    restrictions.reduce(free) do |visible, access|
      visible.or(relation.where(conversations: { inbox_id: access.inbox_id }).where(condition(access)))
    end
  end

  def allows?(conversation)
    access = restrictions.find { |item| item.inbox_id == conversation.inbox_id }
    return true if access.nil?

    Conversation.where(id: conversation.id).where(condition(access)).exists?
  end

  # A pessoa tem alguma caixa restrita: quem tem atalho de "vê tudo" (busca) precisa filtrar.
  def restricted?
    restrictions.any?
  end

  private

  def restrictions
    @restrictions ||= if administrator?
                        []
                      else
                        Crm::InboxAgentAccess.where(account_id: @account.id, user_id: @user.id)
                                             .includes(:agent_pipelines).select(&:restricts?)
                      end
  end

  def administrator?
    AccountUser.find_by(account_id: @account.id, user_id: @user.id)&.administrator?
  end

  def condition(access)
    parts = [own_sql]
    unless access.only_own?
      parts << pipelines_sql(access)
      parts << "NOT EXISTS (#{cards_sql})" if access.triage?
    end
    ActiveRecord::Base.sanitize_sql_array(
      ["(#{parts.compact.join(' OR ')})", { user_id: @user.id, account_id: @account.id, archived: ARCHIVED,
                                            pipeline_ids: access.agent_pipelines.map(&:pipeline_id) }]
    )
  end

  def own_sql
    'conversations.assignee_id = :user_id OR conversations.id IN (SELECT conversation_participants.conversation_id ' \
      'FROM conversation_participants WHERE conversation_participants.user_id = :user_id ' \
      'AND conversation_participants.account_id = :account_id)'
  end

  def pipelines_sql(access)
    return "EXISTS (#{cards_sql})" if access.all_pipelines?
    return if access.agent_pipelines.empty?

    "EXISTS (#{cards_sql} AND crm_access_cards.pipeline_id IN (:pipeline_ids))"
  end

  # Cards da conversa: a principal de cada card ou um vínculo em crm_card_conversations (#1141).
  def cards_sql
    'SELECT 1 FROM crm_cards crm_access_cards WHERE crm_access_cards.account_id = :account_id ' \
      'AND crm_access_cards.status <> :archived AND (crm_access_cards.conversation_id = conversations.id ' \
      'OR crm_access_cards.id IN (SELECT crm_card_conversations.card_id FROM crm_card_conversations ' \
      'WHERE crm_card_conversations.account_id = :account_id AND crm_card_conversations.conversation_id = conversations.id))'
  end
end
