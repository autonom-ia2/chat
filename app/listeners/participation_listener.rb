class ParticipationListener < BaseListener
  include Events::Types

  def assignee_changed(event)
    conversation, _account = extract_conversation_and_account(event)
    release_previous_assignee(conversation, event)
    return if conversation.assignee_id.blank?

    conversation.conversation_participants.find_or_create_by!(user_id: conversation.assignee_id)
  # We have observed race conditions triggering these errors
  # example: Assignment happening via automation, while auto assignment is also configured.
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    Rails.logger.warn "Failed to create conversation participant for account #{conversation.account.id} " \
                      ": user #{conversation.assignee_id} : conversation #{conversation.id}"
  end

  private

  # Acesso por funil (#1148): atribuição não é passe vitalício. Quem tem acesso restrito na caixa e deixa de ser o
  # atendente deixa também de ser participante, e volta a ver a conversa só pelo funil (decisão do Rodrigo, 11/10).
  # Sem acesso restrito, nada muda.
  def release_previous_assignee(conversation, event)
    previous_id = Array(event.data[:changed_attributes].to_h.with_indifferent_access[:assignee_id]).first
    return if previous_id.blank? || previous_id == conversation.assignee_id

    previous = User.find_by(id: previous_id)
    return if previous.blank?
    return unless Crm::Access::ConversationScope.new(user: previous, account: conversation.account).restricted_in?(conversation.inbox_id)

    conversation.conversation_participants.where(user_id: previous_id).destroy_all
  end
end
