# Acesso por funil nos cards (multifunil 8/11, #1148, parte C): o Kanban, a lista, o calendário, a exportação e o
# tempo real do CRM não mostram card de funil que a pessoa não tem. Mesma linha de acesso da conversa
# (Crm::Access::ConversationScope): sem linha, nada muda.
#
# Numa caixa com restrição, a pessoa vê o card quando:
# - é a dona do card, ou atende ou participa da conversa principal dele (o que é dela sempre aparece);
# - senão, se não é "Só as suas": o funil do card é um dos dela (ou ela tem todos os funis).
# A triagem não se aplica a card: card sempre tem funil. Card sem caixa (avulso) não é restringido aqui.
class Crm::Access::CardScope
  def initialize(user:, account:, account_user: nil)
    @user = user
    @account = account
    @conversation_scope = Crm::Access::ConversationScope.new(user: user, account: account, account_user: account_user)
  end

  def apply(cards)
    restrictions = @conversation_scope.restricted_inbox_ids.map { |inbox_id| @conversation_scope.access_for(inbox_id) }
    return cards if restrictions.empty?

    free = cards.where.not(crm_cards: { inbox_id: restrictions.map(&:inbox_id) }).or(cards.where(crm_cards: { inbox_id: nil }))
    restrictions.reduce(free) do |visible, access|
      visible.or(cards.where(crm_cards: { inbox_id: access.inbox_id }).where(condition(access)))
    end
  end

  def restricted?
    @conversation_scope.restricted?
  end

  # A mesma regra como condição SQL para consultas cruas (a soma da CTWA, #1148 PR D); nil sem restrição.
  def ids_condition
    return unless restricted?

    "crm_cards.id IN (#{apply(Crm::Card.where(account_id: @account.id)).select(:id).to_sql})"
  end

  def allows?(card)
    return true if card.inbox_id.nil?

    access = @conversation_scope.access_for(card.inbox_id)
    access.nil? || Crm::Card.where(id: card.id).where(condition(access)).exists?
  end

  # Mover ou gravar o card num funil: a pessoa precisa ter esse funil na caixa do card (o funil do card decide quem vê
  # a conversa; sem isto, mover o card para o próprio funil destravaria a conversa de outro).
  def pipeline_allowed?(inbox_id, pipeline_id)
    access = inbox_id && @conversation_scope.access_for(inbox_id)
    return true if access.nil?
    return false if access.only_own?

    access.all_pipelines? || access.agent_pipelines.map(&:pipeline_id).include?(pipeline_id.to_i)
  end

  private

  def condition(access)
    parts = [own_sql]
    parts << pipelines_sql(access) unless access.only_own?
    ActiveRecord::Base.sanitize_sql_array(
      ["(#{parts.compact.join(' OR ')})", { user_id: @user.id, account_id: @account.id,
                                            pipeline_ids: access.agent_pipelines.map(&:pipeline_id) }]
    )
  end

  def own_sql
    'crm_cards.owner_id = :user_id OR crm_cards.conversation_id IN (SELECT conversations.id FROM conversations ' \
      'WHERE conversations.account_id = :account_id AND conversations.assignee_id = :user_id) ' \
      'OR crm_cards.conversation_id IN (SELECT conversation_participants.conversation_id FROM conversation_participants ' \
      'WHERE conversation_participants.account_id = :account_id AND conversation_participants.user_id = :user_id)'
  end

  def pipelines_sql(access)
    return 'TRUE' if access.all_pipelines?
    return if access.agent_pipelines.empty?

    'crm_cards.pipeline_id IN (:pipeline_ids)'
  end
end
