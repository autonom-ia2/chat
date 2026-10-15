# #1638: o WhatsApp Híbrido (#1489) troca o aviso "mensagem não suportada" pelo texto real e publica
# `whatsapp_hybrid.message_recovered`. Se a IA de assunto já tinha decidido em cima do aviso, a mensagem do cliente
# volta para a pergunta do assunto, pelo mesmo caminho da mensagem nova. O que reabre e o que fica é do Identifier
# (Crm::Subjects::Reabertura): escolha da pessoa e sugestão esperando não mudam.
class Crm::Subjects::MensagemRecuperada
  def self.call(payload)
    return unless Crm::Config.enabled?

    ids = payload.to_h.symbolize_keys
    message = Message.find_by(id: ids[:message_id], conversation_id: ids[:conversation_id], account_id: ids[:account_id])
    return if message.blank? || message.private?

    Crm::Subjects.identificar_depois(message)
  end
end
