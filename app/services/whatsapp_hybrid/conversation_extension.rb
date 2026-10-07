# Prepend em Conversation (chat#1067): com WhatsApp Híbrido pronto, a conversa fora da janela de 24h
# continua respondível (o envio sai pelo WhatsApp API). A janela oficial segue disponível em
# Conversations::MessageWindowService, usada pelo roteador para escolher a Cloud.
module WhatsappHybrid::ConversationExtension
  def can_reply?
    return true if super

    whatsapp_api_reply?
  end

  # A próxima resposta em texto livre sai pelo WhatsApp API (janela oficial fechada, híbrido pronto).
  # O editor usa isto para avisar o agente. Lista de conversas chama isto para cada item: fora das
  # contas liberadas ou de caixas WhatsApp, nem consulta o banco.
  def whatsapp_api_reply?
    return false unless inbox&.channel_type == 'Channel::Whatsapp'
    return false unless WhatsappHybrid::Config.account_allowed?(account_id)
    return false unless WhatsappHybrid::Config.hybrid_inbox?(inbox_id)

    WhatsappHybrid::Router.new(self).web_reply_available?
  end
end
