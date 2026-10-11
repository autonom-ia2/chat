class Crm::Cards::VisibleScopeQuery
  def initialize(scope:, account:, user:, account_user:)
    @scope = scope
    @account = account
    @user = user
    @account_user = account_user
  end

  def perform
    base = @scope.where(account_id: @account.id)
    return base if administrator?
    return base.none if @user.blank?

    # Acesso por funil (#1148, parte C): o card de funil que a pessoa não tem não aparece no CRM.
    Crm::Access::CardScope.new(user: @user, account: @account, account_user: @account_user).apply(visible_to_agent(base))
  end

  private

  def visible_to_agent(base)
    base.where(id: all_inbox_cards(base).select(:id))
        .or(base.where(id: assigned_only_cards(base).select(:id)))
        .or(base.where(id: owned_standalone_cards(base).select(:id)))
  end

  def all_inbox_cards(base)
    base.where(inbox_id: user_inbox_ids).where.not(inbox_id: assigned_only_inbox_ids)
  end

  def assigned_only_cards(base)
    owned_cards(base).or(assigned_conversation_cards(base)).or(participating_conversation_cards(base))
  end

  def owned_cards(base)
    base.where(inbox_id: assigned_only_inbox_ids, owner_id: @user.id)
  end

  def assigned_conversation_cards(base)
    base.where(inbox_id: assigned_only_inbox_ids, conversation_id: assigned_conversation_ids)
  end

  def participating_conversation_cards(base)
    base.where(inbox_id: assigned_only_inbox_ids, conversation_id: participant_conversation_ids)
  end

  def owned_standalone_cards(base)
    base.where(inbox_id: nil, owner_id: @user.id)
  end

  def user_inbox_ids
    @user_inbox_ids ||= @user.inboxes.where(account_id: @account.id).select(:id)
  end

  def assigned_only_inbox_ids
    @assigned_only_inbox_ids ||= Crm::InboxSetting.assigned_only
                                                  .where(account_id: @account.id, inbox_id: user_inbox_ids)
                                                  .select(:inbox_id)
  end

  def assigned_conversation_ids
    @assigned_conversation_ids ||= @account.conversations.where(assignee_id: @user.id).select(:id)
  end

  def participant_conversation_ids
    @participant_conversation_ids ||= ConversationParticipant
                                      .where(account_id: @account.id, user_id: @user.id)
                                      .select(:conversation_id)
  end

  def administrator?
    @account_user&.administrator?
  end
end
