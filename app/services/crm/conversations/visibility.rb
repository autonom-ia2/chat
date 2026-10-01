class Crm::Conversations::Visibility
  def initialize(account:, user:, account_user:)
    @account = account
    @user = user
    @account_user = account_user
  end

  def visible?(conversation)
    return false unless base_visible?(conversation)
    return true if unrestricted_inbox?(conversation)

    assigned_or_participating?(conversation)
  end

  # SQL equivalent of visible? for filters/counts. Filtering after pagination
  # would still expose matches or drop authorized rows from the current page.
  def scope(conversations)
    base = conversations.where(account_id: @account.id)
    return base if administrator?
    return base.none if @user.blank?

    unrestricted = base.where(inbox_id: user_inbox_ids).where.not(inbox_id: assigned_only_inbox_ids)
    restricted = base.where(inbox_id: assigned_only_inbox_ids)
    participants = ConversationParticipant.where(account_id: @account.id, user_id: @user.id).select(:conversation_id)
    unrestricted.or(restricted.where(assignee_id: @user.id)).or(restricted.where(id: participants))
  end

  private

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
