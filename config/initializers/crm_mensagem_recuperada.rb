# Multifunil (#1638): quando o WhatsApp Híbrido (#1489) recupera o texto real de uma mensagem "não suportada", a IA de
# assunto relê a conversa (Crm::Subjects::MensagemRecuperada). O nome do evento fica escrito aqui como texto para não
# carregar o serviço no boot. Inerte até o #1489 publicar o evento.
#
# O assinante nunca derruba quem publica: erro fica no log, só com ids e classe (a mensagem da exceção pode trazer dado).
ActiveSupport::Notifications.subscribe('whatsapp_hybrid.message_recovered') do |*, payload|
  Crm::Subjects::MensagemRecuperada.call(payload)
rescue StandardError => e
  ids = payload.to_h.symbolize_keys
  Rails.logger.error(
    "[crm][subjects][mensagem_recuperada] nao_reenfileirado message_id=#{ids[:message_id]} " \
    "conversation_id=#{ids[:conversation_id]} account_id=#{ids[:account_id]} #{e.class.name}"
  )
end
