class Crm::Conversations::Visibility
  def initialize(account:, user:, account_user:)
    @account = account
    @user = user
    @account_user = account_user
  end

  # #1849 (D7): quem não vê a base de contatos recebe o contato do card enxuto, sem empresa, e não filtra por empresa.
  def full_contact?
    return @full_contact if defined?(@full_contact)

    @full_contact = Crm::Cards::ContactReading.full?(user: @user, account_user: @account_user)
  end

  # Anúncio de origem (#2271): quem lê (pessoa ou robô) vê o anúncio que trouxe o card? Sem identidade, não.
  def anuncio_visivel?
    return @anuncio_visivel if defined?(@anuncio_visivel)

    @anuncio_visivel = Crm::AnuncioDeOrigem.ve_no_contexto?(@user, @account_user)
  end

  # Acesso por funil (#1148, parte C): o CRM passa pela mesma regra da lista de conversas.
  def visible?(conversation)
    return false unless base_visible?(conversation)
    return false unless funnel_scope.allows?(conversation)
    return true if unrestricted_inbox?(conversation)

    assigned_or_participating?(conversation)
  end

  # SQL equivalent of visible? for filters/counts. Filtering after pagination
  # would still expose matches or drop authorized rows from the current page.
  # Kanban e lista: a regra do funil para todas as conversas da página de uma vez (#1148, parte C).
  def preload(conversations)
    funnel_scope.preload(conversations)
  end

  # Cards de uma página (Kanban, lista, exportação, calendário, drawer): a conversa principal e as vinculadas de cada
  # card de uma vez. Sem acesso por funil, nada a fazer.
  def preload_cards(cards)
    return unless funnel_scope.restricted?

    cards = cards.compact
    linked = Crm::CardConversation.where(account_id: @account.id, card_id: cards.map(&:id)).pluck(:conversation_id)
    funnel_scope.preload_ids(cards.map(&:conversation_id) + linked)
  end

  # Vê todas as conversas da conta: o `scope` abaixo não filtra nada (filtro de visibilidade pode ser pulado).
  def all_conversations?
    administrator?
  end

  def scope(conversations)
    base = conversations.where(account_id: @account.id)
    return base if all_conversations?
    return base.none if @user.blank?

    unrestricted = base.where(inbox_id: user_inbox_ids).where.not(inbox_id: assigned_only_inbox_ids)
    restricted = base.where(inbox_id: assigned_only_inbox_ids)
    participants = ConversationParticipant.where(account_id: @account.id, user_id: @user.id).select(:conversation_id)
    funnel_scope.apply(unrestricted.or(restricted.where(assignee_id: @user.id)).or(restricted.where(id: participants)))
  end

  private

  def funnel_scope
    @funnel_scope ||= Crm::Access::ConversationScope.new(user: @user, account: @account, account_user: @account_user)
  end

  def base_visible?(conversation)
    return false if conversation.blank?
    return false unless conversation.account_id == @account.id
    return true if administrator?
    return false if @user.blank?

    user_has_inbox_access?(conversation)
  end

  def unrestricted_inbox?(conversation)
    administrator? || !assigned_only?(conversation)
  end

  def assigned_or_participating?(conversation)
    conversation.assignee_id == @user.id || conversation_participant?(conversation)
  end

  def user_has_inbox_access?(conversation)
    user_inbox_ids.include?(conversation.inbox_id)
  end

  def assigned_only?(conversation)
    assigned_only_inbox_ids.include?(conversation.inbox_id)
  end

  def administrator?
    @account_user&.administrator?
  end

  def user_inbox_ids
    @user_inbox_ids ||= @user.inboxes.where(account_id: @account.id).pluck(:id)
  end

  def assigned_only_inbox_ids
    @assigned_only_inbox_ids ||= @account.crm_inbox_settings
                                         .assigned_only
                                         .where(inbox_id: user_inbox_ids)
                                         .pluck(:inbox_id)
  end

  def conversation_participant?(conversation)
    participant_cache.fetch(conversation.id) do
      participant_cache[conversation.id] = participant?(conversation)
    end
  end

  def participant?(conversation)
    if conversation.association(:conversation_participants).loaded?
      return conversation.conversation_participants.any? { |participant| participant.user_id == @user.id }
    end

    conversation.conversation_participants.exists?(user_id: @user.id)
  end

  def participant_cache
    @participant_cache ||= {}
  end
end
