# Quem, entre os membros da caixa, pode ver a conversa pelo acesso por funil (#1148, parte B): tempo real, notificações,
# contadores e rodízio usam isto para não entregar a conversa a quem a lista e o link já escondem
# (Crm::Access::ConversationScope, parte A).
#
# Sem linha de acesso restritiva na caixa (o caso de todo mundo hoje), uma consulta só e nada muda. Com restrição, cada
# pessoa restrita passa pela mesma regra do link (#allows?); quem não é restrito não é consultado.
class Crm::Access::Recipients
  # Membros da caixa que podem ver a conversa: o tempo real e as notificações não entregam o que a lista esconde.
  def self.inbox_members(conversation)
    new(conversation).filter(conversation.inbox.members)
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
    @blocked_user_ids ||= restricted_accesses.reject { |access| visible_to?(access) }.map(&:user_id)
  end

  private

  def restricted_accesses
    Crm::InboxAgentAccess.where(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id)
                         .includes(:user, :agent_pipelines).select(&:restricts?)
  end

  def visible_to?(access)
    Crm::Access::ConversationScope.new(user: access.user, account: @conversation.account).allows?(@conversation)
  end
end
