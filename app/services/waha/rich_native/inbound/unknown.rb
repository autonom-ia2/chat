# `waha_unknown` (chat#1709, fase 3): mensagem do cliente de um tipo que o conector não converte (evento, figurinha de
# pacote novo, visualização única que o motor não abre). Antes era uma nota privada (só a equipe via, com o link do
# job). Agora é uma bolha curta do cliente, como no WhatsApp oficial: o mesmo texto e a mesma marca `is_unsupported`
# do Chatwoot (incoming_message_base_service.rb), e a tela mostra a bolha "não suportada" do upstream (abra no
# celular). O tipo original fica em `waha_unknown_type`. Mensagem que saiu do celular da empresa (from_me) continua
# nota, como antes.
module Waha::RichNative::Inbound::Unknown
  TEXT_KEY = 'conversations.messages.whatsapp.unsupported_message'.freeze

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && data['from_me'] != true

    contact = message.conversation&.contact
    return if contact.nil?

    message.message_type = :incoming
    message.private = false
    message.sender = contact
    message.content = I18n.t(TEXT_KEY, locale: message.account.locale, default: I18n.t(TEXT_KEY))
    message.content_attributes = message.content_attributes.to_h.merge('is_unsupported' => true,
                                                                       'waha_unknown_type' => data['content_type'])
  end
end
