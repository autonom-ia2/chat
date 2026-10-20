module Enterprise::Conversations::PermissionFilterService
  def perform
    return filter_by_permissions(permissions) if user_has_custom_role?

    super
  end

  private

  def user_has_custom_role?
    user_role == 'agent' && account_user&.custom_role_id.present?
  end

  def permissions
    account_user&.permissions || []
  end

  # conversation_manage sees every conversation of the user's inboxes. The two limited keys add
  # up, as in ConversationPolicy#show? (#1157): before, holding both applied only the first, and
  # the list hid conversations the person could open by link.
  def filter_by_permissions(permissions)
    return accessible_conversations if permissions.include?('conversation_manage')

    scopes = []
    scopes << filter_unassigned_and_mine if permissions.include?('conversation_unassigned_manage')
    scopes << filter_participating_and_mine if permissions.include?('conversation_participating_manage')
    scopes.reduce(:or) || Conversation.none
  end

  def filter_participating_and_mine
    conversations = accessible_conversations
    participant_conversation_ids = ConversationParticipant.where(account_id: account.id, user_id: user.id).select(:conversation_id)

    conversations
      .where(assignee_id: user.id)
      .or(conversations.where(id: participant_conversation_ids))
  end

  def filter_unassigned_and_mine
    conversations = accessible_conversations
    conversations.unassigned.or(conversations.assigned_to(user))
  end
end
