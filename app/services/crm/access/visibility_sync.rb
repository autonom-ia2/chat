# Quando o card muda de funil, de status ou de conversa, ou nasce (#1148, parte C), muda quem vê a conversa. A tela de
# quem passou a ver recebe a conversa (conversation.updated); a de quem deixou de ver a tira da lista
# (conversation.access_revoked). Conversa aberta e sem atendente volta ao rodízio, que agora só escolhe quem tem o funil
# do card. Conta sem acesso configurado: nada acontece.
module Crm::Access::VisibilitySync
  REVOKED = 'conversation.access_revoked'.freeze

  module_function

  def perform(conversation)
    return if conversation.nil?
    return unless Crm::Access::AccountFlag.any?(conversation.account_id)

    recipients = Crm::Access::Recipients.new(conversation)
    broadcast(conversation, visible_tokens(conversation, recipients), Events::Types::CONVERSATION_UPDATED,
              conversation.push_event_data)
    broadcast(conversation, User.where(id: recipients.blocked_user_ids).pluck(:pubsub_token), REVOKED, { id: conversation.id })
    reassign(conversation)
  end

  def visible_tokens(conversation, recipients)
    users = recipients.filter(conversation.inbox.members).to_a | conversation.account.administrators.to_a
    users.filter_map(&:pubsub_token)
  end

  def broadcast(conversation, tokens, event, data)
    return if tokens.blank?

    ActionCableBroadcastJob.perform_later(tokens.uniq, event, data.merge(account_id: conversation.account_id))
  end

  # A conversa sem atendente que ganhou funil volta ao rodízio (decisão de 11/10: o card nasce depois da conversa).
  def reassign(conversation)
    return unless conversation.open? && conversation.assignee_id.blank? && conversation.inbox.enable_auto_assignment?

    if conversation.inbox.auto_assignment_v2_enabled?
      AutoAssignment::AssignmentJob.enqueue_for_inbox(conversation.inbox_id)
    else
      AutoAssignment::AgentAssignmentService.new(conversation: conversation,
                                                 allowed_agent_ids: conversation.inbox.member_ids_with_assignment_capacity).perform
    end
  end
end
