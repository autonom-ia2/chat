# O funil do card libera a visão da conversa (multifunil 8/11, #1148, R2–R5). Um lugar só para a regra. Neste PR (A)
# leem daqui a lista de conversas, o link e a busca; tempo real, notificações e contadores entram no PR B, e o CRM
# (Crm::Conversations::Visibility, Broadcaster) no PR C. Até lá nenhuma linha de acesso pode ser criada (ver #1149).
#
# Por pessoa e por caixa (Crm::InboxAgentAccess). Sem linha, ou linha que libera tudo, nada muda: vale a regra de caixa
# de sempre (R5). Com restrição, numa caixa a pessoa vê a conversa quando:
# - está atribuída a ela ou ela participa (atribuído e participante sempre veem, decisão do Rodrigo em 11/10);
# - senão, se não é "Só as suas": algum card da conversa está num funil dela, ou a conversa não tem card e ela tem a
#   triagem (R3).
# Administrador vê tudo. Card arquivado, resolvido ou cancelado não conta como card (RELEASED).
#
# Este filtro só RESTRINGE: quem chama já aplicou a regra de caixa (membro da caixa, time, função personalizada).
class Crm::Access::ConversationScope
  # Card que não prende a conversa ao funil (decisão do Rodrigo, 11/10): arquivado, e resolvido ou cancelado (funil de
  # atendimento: o caso acabou, a conversa reaberta volta para a triagem). Ganho e perdido seguem com o funil.
  RELEASED = Crm::Card.statuses.values_at(:archived, :resolved, :cancelled).freeze

  # account_user: quem já tem (a Policy) passa e poupa a consulta.
  def initialize(user:, account:, account_user: nil)
    @user = user
    @account = account
    @account_user = account_user
  end

  # As conversas da relação que a pessoa pode ver.
  def apply(relation)
    return relation if restrictions.empty?

    free = relation.where.not(conversations: { inbox_id: restrictions.map(&:inbox_id) })
    restrictions.reduce(free) do |visible, access|
      visible.or(relation.where(conversations: { inbox_id: access.inbox_id }).where(condition(access)))
    end
  end

  # Guarda o resultado por conversa: o payload de um card pergunta várias vezes pela mesma conversa (#1148, parte C).
  def allows?(conversation)
    access = restrictions.find { |item| item.inbox_id == conversation.inbox_id }
    return true if access.nil?

    allowed_cache.fetch(conversation.id) do
      allowed_cache[conversation.id] = Conversation.where(id: conversation.id).where(condition(access)).exists?
    end
  end

  # Responde de uma vez para várias conversas (Kanban, lista): uma consulta em vez de uma por conversa.
  def preload(conversations)
    preload_ids(conversations.compact.map(&:id))
  end

  def preload_ids(conversation_ids)
    return if restrictions.empty?

    pending = conversation_ids.compact.uniq.reject { |id| allowed_cache.key?(id) }
    return if pending.empty?

    allowed = apply(Conversation.where(id: pending)).pluck(:id).to_set
    pending.each { |id| allowed_cache[id] = allowed.include?(id) }
  end

  # A pessoa tem alguma caixa restrita: quem tem atalho de "vê tudo" (busca) precisa filtrar.
  def restricted?
    restrictions.any?
  end

  def restricted_inbox_ids
    restrictions.map(&:inbox_id)
  end

  # A linha que restringe a pessoa nesta caixa, ou nil (CardScope usa a mesma leitura).
  def access_for(inbox_id)
    restrictions.find { |access| access.inbox_id == inbox_id }
  end

  # A mesma regra do #condition, avaliada em memória sobre os dados de UMA conversa (Crm::Access::Recipients, que
  # decide muitas pessoas por evento). Mudou a regra num, mude no outro: o spec de paridade compara os dois.
  # facts: assignee_id, participant_ids, card_pipeline_ids (cards que prendem, ver RELEASED).
  def self.visible_by_facts?(access, user_id, facts)
    return true if facts[:assignee_id] == user_id || facts[:participant_ids].include?(user_id)
    return false if access.only_own?

    pipelines = facts[:card_pipeline_ids]
    return access.triage? if pipelines.empty?
    return true if access.all_pipelines?

    access.agent_pipelines.map(&:pipeline_id).intersect?(pipelines)
  end

  private

  def allowed_cache
    @allowed_cache ||= {}
  end

  # Uma consulta só para quem não tem linha (o caso de todo mundo hoje); o papel só é lido quando há restrição.
  # AgentBot não tem acesso por funil: o id dele pode coincidir com o de uma pessoa.
  def restrictions
    @restrictions ||= begin
      rows = if @user.is_a?(User) && Crm::Access::AccountFlag.any?(@account.id)
               Crm::InboxAgentAccess.where(account_id: @account.id, user_id: @user.id)
                                    .includes(:agent_pipelines).select(&:restricts?)
             else
               []
             end
      rows.empty? || unrestricted_role? ? [] : rows
    end
  end

  # Administrador vê tudo. Usuário de integração (token do n8n, MCP) não tem acesso por funil nem com linha antiga
  # (#1148, PR D): o alcance dele é o escopo do token.
  def unrestricted_role?
    account_user = @account_user || AccountUser.find_by(account_id: @account.id, user_id: @user.id)
    account_user.present? && (account_user.administrator? || account_user.integration?)
  end

  def condition(access)
    parts = [own_sql]
    unless access.only_own?
      parts << pipelines_sql(access)
      parts << "NOT (#{card_exists_sql})" if access.triage?
    end
    ActiveRecord::Base.sanitize_sql_array(
      ["(#{parts.compact.join(' OR ')})", { user_id: @user.id, account_id: @account.id, released: RELEASED,
                                            pipeline_ids: access.agent_pipelines.map(&:pipeline_id) }]
    )
  end

  def own_sql
    'conversations.assignee_id = :user_id OR conversations.id IN (SELECT conversation_participants.conversation_id ' \
      'FROM conversation_participants WHERE conversation_participants.user_id = :user_id ' \
      'AND conversation_participants.account_id = :account_id)'
  end

  def pipelines_sql(access)
    return card_exists_sql if access.all_pipelines?
    return if access.agent_pipelines.empty?

    card_exists_sql(' AND crm_access_cards.pipeline_id IN (:pipeline_ids)')
  end

  # A conversa tem card (não arquivado): a principal do card ou um vínculo em crm_card_conversations (#1141). Dois
  # EXISTS em vez de um OR dentro da subconsulta: cada um entra pelo índice da conversa (idx_crm_cards_conversation e
  # idx_crm_card_conversations_conversation), e a lista não percorre os cards uma vez por conversa.
  def card_exists_sql(pipeline_filter = '')
    '(EXISTS (SELECT 1 FROM crm_cards crm_access_cards WHERE crm_access_cards.account_id = :account_id ' \
      "AND crm_access_cards.conversation_id = conversations.id AND crm_access_cards.status NOT IN (:released)#{pipeline_filter}) " \
      'OR EXISTS (SELECT 1 FROM crm_card_conversations crm_access_links INNER JOIN crm_cards crm_access_cards ' \
      'ON crm_access_cards.id = crm_access_links.card_id AND crm_access_cards.account_id = :account_id ' \
      'WHERE crm_access_links.account_id = :account_id AND crm_access_links.conversation_id = conversations.id ' \
      "AND crm_access_cards.status NOT IN (:released)#{pipeline_filter}))"
  end
end
