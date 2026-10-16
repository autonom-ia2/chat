# Quem, entre os membros da caixa, pode ver a conversa pelo acesso por funil (#1148, parte B): tempo real, notificações,
# contadores e rodízio usam isto para não entregar a conversa a quem a lista e o link já escondem
# (Crm::Access::ConversationScope, parte A).
#
# Sem linha de acesso restritiva na caixa (o caso de todo mundo hoje), uma consulta só e nada muda. Com restrição, os
# dados da conversa são lidos uma vez (atendente, participantes, funis e donos dos cards) e cada pessoa restrita é
# avaliada em
# memória pela mesma regra do link (ConversationScope.visible_by_facts?): o custo não cresce por pessoa, e isto roda
# dentro do envio de cada mensagem.
class Crm::Access::Recipients
  # Membros da caixa que podem ver a conversa: o tempo real e as notificações não entregam o que a lista esconde.
  def self.inbox_members(conversation)
    new(conversation).filter(conversation.inbox.members)
  end

  # Card (parte C): ver Crm::Access::CardRecipients.
  def self.card_blocked_user_ids(card) = Crm::Access::CardRecipients.new(card).blocked_user_ids

  # Quem recebe algo do card fora da lista de destinatários (o responsável pelo lembrete): sem card, nada a esconder.
  def self.card_visible_to?(card, user)
    card.nil? || card_blocked_user_ids(card).exclude?(user.id)
  end

  # Administrador e usuário de integração não têm acesso por funil, como no ConversationScope (#1148, PR D).
  def self.unrestricted_user_ids(account_id, user_ids)
    account_users = AccountUser.where(account_id: account_id, user_id: user_ids)
    account_users.administrator.or(account_users.where(integration: true)).pluck(:user_id)
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
      people = restricted_people
      people.empty? ? [] : blocked_among(people)
    end
  end

  # Quem tem linha restritiva nesta caixa (fora administrador): só a visão dessas pessoas depende do card
  # (Crm::Access::VisibilitySync).
  def restricted_user_ids
    restricted_people.map(&:user_id)
  end

  private

  # Administrador vê tudo, mesmo com linha (como no ConversationScope).
  def restricted_people
    @restricted_people ||= begin
      accesses = restricted_accesses
      admins = if accesses.empty?
                 []
               else
                 self.class.unrestricted_user_ids(@conversation.account_id, accesses.map(&:user_id))
               end
      accesses.reject { |access| admins.include?(access.user_id) }
    end
  end

  def restricted_accesses
    return [] unless Crm::Access::AccountFlag.any?(@conversation.account_id)

    Crm::InboxAgentAccess.where(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id)
                         .includes(:agent_pipelines).select(&:restricts?)
  end

  def blocked_among(people)
    facts = conversation_facts
    people.reject { |access| Crm::Access::ConversationScope.visible_by_facts?(access, access.user_id, facts) }.map(&:user_id)
  end

  def conversation_facts
    cards = binding_cards
    {
      assignee_id: @conversation.assignee_id,
      participant_ids: ConversationParticipant.where(conversation_id: @conversation.id).pluck(:user_id),
      card_pipeline_ids: cards.map(&:first).uniq,
      card_owner_ids: cards.filter_map(&:last).uniq
    }
  end

  # [funil, status, dono] dos cards que prendem a conversa: a principal de cada card ou um vínculo em
  # crm_card_conversations. Card aberto manda (decisão do Rodrigo em 11/10): com card aberto, só os abertos; senão os
  # ganhos e perdidos. Mesma regra do ConversationScope#binding_card_sql, para o funil e para o dono (#1652).
  def binding_cards
    linked = Crm::CardConversation.where(account_id: @conversation.account_id, conversation_id: @conversation.id).select(:card_id)
    cards = Crm::Card.where(account_id: @conversation.account_id)
                     .where.not(status: Crm::Access::ConversationScope::RELEASED)
    rows = cards.where(conversation_id: @conversation.id).or(cards.where(id: linked)).distinct.pluck(:pipeline_id, :status, :owner_id)
    open_status = Crm::Card.statuses.key(Crm::Access::ConversationScope::OPEN.first)
    rows.select { |_pipeline_id, status, _owner_id| status == open_status }.presence || rows
  end
end
