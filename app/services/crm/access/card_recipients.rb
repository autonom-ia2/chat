# Quem o funil esconde não recebe o card em tempo real (#1148, parte C). Mesma regra do Crm::Access::CardScope,
# avaliada em memória: dono, atendente e participante da conversa principal sempre recebem; senão, o funil do card
# precisa ser da pessoa (fora "Só as suas"). Administrador sempre recebe. Sem linha restritiva na caixa, nada muda.
class Crm::Access::CardRecipients
  def initialize(card)
    @card = card
  end

  def blocked_user_ids
    accesses = restricted_accesses
    return [] if accesses.empty?

    keep = admin_ids(accesses) | own_user_ids
    accesses.reject { |access| keep.include?(access.user_id) || pipeline_allowed?(access) }.map(&:user_id)
  end

  private

  def restricted_accesses
    return [] if @card.inbox_id.nil?
    return [] unless Crm::Access::AccountFlag.any?(@card.account_id)

    Crm::InboxAgentAccess.where(account_id: @card.account_id, inbox_id: @card.inbox_id)
                         .includes(:agent_pipelines).select(&:restricts?)
  end

  def admin_ids(accesses)
    Crm::Access::Recipients.unrestricted_user_ids(@card.account_id, accesses.map(&:user_id))
  end

  def own_user_ids
    conversation = @card.primary_conversation
    ids = [@card.owner_id, conversation&.assignee_id]
    ids += ConversationParticipant.where(conversation_id: conversation.id).pluck(:user_id) if conversation
    ids.compact
  end

  def pipeline_allowed?(access)
    return false if access.only_own?

    access.all_pipelines? || access.agent_pipelines.map(&:pipeline_id).include?(@card.pipeline_id)
  end
end
