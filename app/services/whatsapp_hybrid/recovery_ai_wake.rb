# Quando chamar a nossa IA depois de recuperar uma mensagem "não suportada" (chat#1489). O MessageListener ignorou o
# aviso; aqui ela é chamada uma vez, e só se for seguro:
# - a recuperação chegou em até 2 minutos do recebimento;
# - a mensagem ainda é a última da conversa: nem o cliente mandou outra, nem alguém (atendente ou IA) respondeu depois.
#   O Responder responde à última mensagem do cliente; acordá-lo por uma mensagem velha responderia de novo a outra.
# Modelo de outra empresa (`unsupported_type: hsm`) acorda a IA como qualquer outra: o modelo de agentes já instrui a
# não dar trela para robô (decisão do Rodrigo, 15/10/2026).
module WhatsappHybrid::RecoveryAiWake
  AI_WAIT = 2.minutes
  # Notas privadas e atividades não contam: não são conversa com o cliente.
  CONVERSATION_TYPES = %i[incoming outgoing template].freeze

  module_function

  def call(message)
    return unless wake?(message)

    ::Autonomia::Agents::Operate::ReplyJob.perform_later(message.conversation_id, message.id)
  end

  def wake?(message)
    Time.current <= message.created_at + AI_WAIT && !followed?(message)
  end

  def followed?(message)
    message.conversation.messages.where(id: (message.id + 1)..)
           .exists?(private: false, message_type: CONVERSATION_TYPES)
  end
end
