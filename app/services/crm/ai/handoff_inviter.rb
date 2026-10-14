# R3 "bot-recepcionista": convida um agente humano para a conversa SEM atribuir
# e SEM calar o bot. Adiciona o agente como participante e dispara uma notificação
# interna (push + email + sininho) via NotificationBuilder. O bot continua dono e
# atendendo o cliente até o humano se auto-atribuir — aí a atribuição cala o bot
# (reset_agent_bot_when_assignee_present). Sem Message no thread → sem vazamento
# p/ webhook n8n (message_created não dispara).
class Crm::Ai::HandoffInviter
  # `idempotente`: o convite que a pessoa ainda não leu vale como feito; não cria outra notificação (o motor de entrega
  # pode refazer a passagem depois de uma falha, #1454). A reavisada do EscalationJob avisa de novo de propósito.
  def initialize(conversation:, agent:, idempotente: false)
    @conversation = conversation
    @agent = agent
    @idempotente = idempotente
  end

  # true só se o convite efetivou de verdade: participante garantido E notificação
  # criada. Se o NotificationBuilder no-opar (contato bloqueado / agente sem acesso
  # à conversa), retorna false → o executor faz rollback (não grava participante nem
  # cooldown) e pula como 'invite_failed'. Não registra convite que ninguém recebe.
  def perform
    # Acesso por funil (#1148): o convite do sistema não dá participação a quem o funil esconde (participante sempre
    # vê). false → o executor faz rollback e registra 'invite_failed'.
    return false unless Crm::Access::ConversationScope.new(user: @agent, account: @conversation.account).allows?(@conversation)

    add_participant!
    return true if @idempotente && convite_pendente?

    notify!.present?
  rescue ActiveRecord::RecordInvalid
    false
  end

  private

  def convite_pendente?
    Notification.exists?(user_id: @agent.id, account_id: @conversation.account_id, read_at: nil,
                         notification_type: Notification.notification_types[:conversation_handoff_request],
                         primary_actor_type: 'Conversation', primary_actor_id: @conversation.id)
  end

  def add_participant!
    ConversationParticipant.find_or_create_by!(conversation: @conversation, user: @agent)
  end

  # secondary_actor: nil de propósito — o convite é do sistema/IA, não de um
  # usuário. push_event_data trata secondary_actor nil.
  def notify!
    NotificationBuilder.new(
      notification_type: 'conversation_handoff_request',
      user: @agent,
      account: @conversation.account,
      primary_actor: @conversation,
      secondary_actor: nil
    ).perform
  end
end
