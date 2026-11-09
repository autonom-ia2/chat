class Crm::Cards::DetailPayloadBuilder
  ACTIVITY_LIMIT = 25
  CONVERSATION_LIMIT = 10
  UNRESOLVED_COMPANY = Object.new.freeze

  def initialize(card:, user:, account_user:, company: UNRESOLVED_COMPANY)
    @card = card
    @account = card.account
    @user = user
    @account_user = account_user
    @company = company
  end

  def perform
    payload_options = { user: @user, account_user: @account_user, conversation_visibility: conversation_visibility }
    payload_options[:company] = @company unless @company.equal?(UNRESOLVED_COMPANY)
    Crm::Cards::PayloadBuilder.new(@card, **payload_options).perform.merge(
      linked_conversations: linked_conversations_payload,
      activities: activities_payload,
      can_edit: can_edit?
    )
  end

  private

  # Acesso por funil (#1148, decisão b; #1149): a tela esconde o que a pessoa não pode mexer neste card.
  def can_edit?
    return true unless @user.is_a?(User)

    Crm::Access::CardGuard.new(user: @user, account: @account, account_user: @account_user).edit_allowed?(@card)
  end

  # Acesso por funil (#1148, parte C): as conversas do card (principal e vinculadas) numa consulta só.
  def conversation_visibility
    @conversation_visibility ||= Crm::Conversations::Visibility.new(account: @account, user: @user, account_user: @account_user)
                                                               .tap { |visibility| visibility.preload_cards([@card]) }
  end

  def linked_conversations_payload
    visible_linked_conversations.map { |conversation| conversation_payload(conversation) }
  end

  def conversation_payload(conversation)
    {
      id: conversation.id,
      display_id: conversation.display_id,
      inbox_id: conversation.inbox_id,
      inbox_name: conversation.inbox&.name,
      contact_id: conversation.contact_id,
      contact_name: conversation.contact&.name,
      status: conversation.status,
      assignee_id: conversation.assignee_id,
      assignee_name: conversation.assignee&.name,
      team_id: conversation.team_id,
      team_name: conversation.team&.name,
      last_activity_at: conversation.last_activity_at&.iso8601,
      created_at: conversation.created_at&.iso8601,
      is_primary: conversation.id == @card.conversation_id
    }
  end

  def visible_linked_conversations
    conversations = @card.linked_conversations
                         .includes(:inbox, :contact, :assignee, :team)
                         .order(updated_at: :desc)
                         .limit(CONVERSATION_LIMIT)
                         .to_a
    # Legacy cards can have conversation_id without the join row introduced
    # later. Keep the primary conversation in the same flat detail contract so
    # the drawer never falls back to the compact card.conversation payload.
    primary = @card.primary_conversation
    conversations << primary if primary.present? && conversations.none? { |conversation| conversation.id == primary.id }
    return conversations if administrator?

    preload_conversation_permissions(conversations)
    funnel_visible(conversations.select { |conversation| conversation_visible_to_agent?(conversation) })
  end

  # Acesso por funil (#1148, parte C): o drawer do card não lista conversa que o funil esconde.
  def funnel_visible(conversations)
    funnel = Crm::Access::ConversationScope.new(user: @user, account: @account)
    return conversations unless funnel.restricted?

    allowed = funnel.apply(@account.conversations.where(id: conversations.map(&:id))).pluck(:id).to_set
    conversations.select { |conversation| allowed.include?(conversation.id) }
  end

  def preload_conversation_permissions(conversations)
    @conversation_ids = conversations.map(&:id)
    @inbox_ids = conversations.filter_map(&:inbox_id)
    @user_inbox_ids = @user.inboxes.where(account_id: @account.id, id: @inbox_ids)
                           .pluck(:id)
                           .to_set
    @assigned_only_inbox_ids = Crm::InboxSetting.assigned_only
                                                .where(account_id: @account.id, inbox_id: @inbox_ids)
                                                .pluck(:inbox_id)
                                                .to_set
    @participant_conversation_ids = ConversationParticipant
                                    .where(account_id: @account.id, user_id: @user.id, conversation_id: @conversation_ids)
                                    .pluck(:conversation_id)
                                    .to_set
  end

  def conversation_visible_to_agent?(conversation)
    return false unless @user_inbox_ids.include?(conversation.inbox_id)
    return true unless @assigned_only_inbox_ids.include?(conversation.inbox_id)

    conversation.assignee_id == @user.id || @participant_conversation_ids.include?(conversation.id)
  end

  def activities_payload
    activities = Crm::Cards::ActivityPayloadBuilder.new(
      account: @account,
      user: @user,
      account_user: @account_user,
      activities: visible_activities.order(created_at: :desc).limit(ACTIVITY_LIMIT).to_a
    ).perform
    Crm::ValorDeVenda.ve_o_card?(@account_user, @card) ? activities : activities.map { |activity| without_value(activity) }
  end

  # Sugestão de etapa da IA (#2150): o 'ai_suggested' grava a etapa sugerida e a confiança; sem crm_manage_ai, o
  # histórico não o traz. O 'ai_dismissed' (só o id) e o 'ai_auto_moved' (o card mudou mesmo de etapa) ficam.
  def visible_activities
    return @card.activities if Crm::SugestaoDeEtapa.le?(@account_user)

    @card.activities.where.not(event_type: 'ai_suggested')
  end

  # Valor de venda (#2075): o ganho grava value_cents na atividade, e a edição grava os campos que o pedido mandou.
  def without_value(activity)
    payload = activity[:payload]
    payload.is_a?(Hash) ? activity.merge(payload: payload.except('value_cents', :value_cents)) : activity
  end

  def administrator?
    @account_user&.administrator?
  end
end
