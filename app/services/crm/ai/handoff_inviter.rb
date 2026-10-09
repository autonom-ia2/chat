# R3 "bot-recepcionista": convida um agente humano para a conversa SEM atribuir
# e SEM calar o bot. Adiciona o agente como participante e dispara uma notificação
# interna (push + email + sininho) via NotificationBuilder. O bot continua dono e
# atendendo o cliente até o humano se auto-atribuir — aí a atribuição cala o bot
# (reset_agent_bot_when_assignee_present). Sem Message no thread → sem vazamento
# p/ webhook n8n (message_created não dispara).
class Crm::Ai::HandoffInviter
  def initialize(conversation:, agent:)
    @conversation = conversation
    @agent = agent
  end

  # true só se o convite efetivou de verdade: participante garantido E notificação
  # criada. Se o NotificationBuilder no-opar (contato bloqueado / agente sem acesso
  # à conversa), retorna false → o executor faz rollback (não grava participante nem
  # cooldown) e pula como 'invite_failed'. Não registra convite que ninguém recebe.
  def perform
    add_participant!
    notify!.present?
  rescue ActiveRecord::RecordInvalid
    false
  end

  private

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
