# Quando chamar a nossa IA depois de recuperar uma mensagem "não suportada" (chat#1489). O MessageListener ignorou o
# aviso; aqui ela é chamada uma vez, e só se for seguro:
# - a recuperação chegou em até 2 minutos do recebimento (2:00 ainda chama);
# - a conversa não está resolvida;
# - ninguém falou depois do aviso. Conta: (a) mensagem do mesmo contato na mesma caixa, em qualquer conversa; (b) resposta
#   pública de uma pessoa (sender User) ou da nossa IA (o AgentBot de um agente da Autonomia nesta caixa) na conversa.
#   Não conta: mensagens do sistema (`template`: fora do horário, saudação, coleta de e-mail), atividades, notas
#   privadas, regras de automação (sem remetente) e outro robô (n8n/AgentBot que não é a nossa IA) que respondeu ao
#   próprio aviso. O Responder responde à última mensagem do cliente; acordá-lo depois de outra resposta repetiria.
# Modelo de outra empresa (`unsupported_type: hsm`) acorda como qualquer outra: o modelo de agentes já instrui a não
# dar trela para robô (decisão do Rodrigo, 15/10/2026).
module WhatsappHybrid::RecoveryAiWake
  AI_WAIT = 2.minutes

  module_function

  def call(message)
    return unless wake?(message)

    ::Autonomia::Agents::Operate::ReplyJob.perform_later(message.conversation_id, message.id)
  end

  def wake?(message)
    Time.current <= message.created_at + AI_WAIT && !message.conversation.resolved? &&
      !contact_spoke_after?(message) && !answered_after?(message)
  end

  def contact_spoke_after?(message)
    Message.where(inbox_id: message.inbox_id, id: (message.id + 1)..)
           .exists?(message_type: :incoming, private: false, sender_type: 'Contact', sender_id: message.sender_id)
  end

  def answered_after?(message)
    replies = message.conversation.messages.where(id: (message.id + 1)..).where(message_type: :outgoing, private: false)
    replies.exists?(sender_type: 'User') || replies.exists?(sender_type: 'AgentBot', sender_id: our_bot_ids(message))
  end

  def our_bot_ids(message)
    ::Autonomia::Agents::AgentInbox.where(inbox_id: message.inbox_id).select(:agent_bot_id)
  end
end
