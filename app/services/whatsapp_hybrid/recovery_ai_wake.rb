# Quando chamar a nossa IA depois de recuperar uma mensagem "não suportada" (chat#1489). O MessageListener ignorou o
# aviso; aqui ela é chamada uma vez, e só se for seguro:
# - a conversa não está resolvida;
# - ninguém falou depois do aviso. Conta: (a) mensagem do mesmo contato na mesma caixa, em qualquer conversa; (b) resposta
#   pública de uma pessoa (sender User) na conversa; (c) resposta da nossa IA (o AgentBot de um agente da Autonomia
#   nesta caixa) a esta mensagem ou a uma mais nova (`autonomia_reply_to_message_id` >= id; sem o id, conta). Não conta:
#   mensagens do sistema (`template`: fora do horário, saudação, coleta de e-mail), atividades, notas privadas, regras de
#   automação (sem remetente), outro robô (n8n/AgentBot que não é a nossa IA) e a nossa IA respondendo a uma mensagem
#   anterior ao aviso. O Responder responde à última mensagem do cliente; acordá-lo depois de outra resposta repetiria;
# - a recuperação chegou em até 2 minutos do recebimento (2:00 ainda chama). Depois disso, a IA fica parada e o motivo
#   vai para o evento `skipped_recuperada_tarde` (Operate::NaoSuportada).
# Modelo de outra empresa (`unsupported_type: hsm`) acorda como qualquer outra: o modelo de agentes já instrui a não
# dar trela para robô (decisão do Rodrigo, 15/10/2026).
module WhatsappHybrid::RecoveryAiWake
  AI_WAIT = 2.minutes
  REPLY_TO_KEY = 'autonomia_reply_to_message_id'.freeze

  module_function

  def call(message)
    return if message.conversation.resolved? || contact_spoke_after?(message) || answered_after?(message)
    return ::Autonomia::Agents::Operate::NaoSuportada.tarde(message) if Time.current > message.created_at + AI_WAIT

    ::Autonomia::Agents::Operate::ReplyJob.perform_later(message.conversation_id, message.id)
  end

  def contact_spoke_after?(message)
    Message.where(inbox_id: message.inbox_id, id: (message.id + 1)..)
           .exists?(message_type: :incoming, private: false, sender_type: 'Contact', sender_id: message.sender_id)
  end

  def answered_after?(message)
    replies = message.conversation.messages.where(id: (message.id + 1)..).where(message_type: :outgoing, private: false)
    return true if replies.exists?(sender_type: 'User')

    replies.where(sender_type: 'AgentBot', sender_id: our_bot_ids(message)).any? do |reply|
      reply_to = reply.content_attributes.to_h[REPLY_TO_KEY]
      reply_to.nil? || reply_to.to_i >= message.id
    end
  end

  def our_bot_ids(message)
    ::Autonomia::Agents::AgentInbox.where(inbox_id: message.inbox_id).select(:agent_bot_id)
  end
end
