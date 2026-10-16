# `waha_unknown` (chat#1709, fase 3): mensagem do cliente de um tipo que o conector não converte (evento, figurinha de
# pacote novo, visualização única que o motor não abre). Antes era uma nota privada (só a equipe via, com o link do
# job). Agora é uma bolha curta do cliente, como no WhatsApp oficial: o mesmo texto e a mesma marca `is_unsupported`
# do Chatwoot (incoming_message_base_service.rb), e a tela mostra a bolha "não suportada" do upstream (abra no
# celular). O tipo, quando o motor sabe, fica em `unsupported_kind` (formato da tela do Frontend geral, #1702):
# poll | gif | pinned | edit | view_once | unknown, pela tabela KINDS (igualdade exata do tipo do proto, sem regex).
# Mensagem que saiu do celular da empresa (from_me) continua nota, como antes.
module Waha::RichNative::Inbound::Unknown
  TEXT_KEY = 'conversations.messages.whatsapp.unsupported_message'.freeze
  KINDS = {
    'pollCreationMessage' => 'poll', 'pollCreationMessageV2' => 'poll', 'pollCreationMessageV3' => 'poll',
    'pinInChatMessage' => 'pinned',
    'editedMessage' => 'edit', 'protocolMessage' => 'edit',
    'viewOnceMessage' => 'view_once', 'viewOnceMessageV2' => 'view_once', 'viewOnceMessageV2Extension' => 'view_once'
  }.freeze
  UNKNOWN_KIND = 'unknown'.freeze

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && data['from_me'] != true
    # O pedido (Waha::RichNative::Inbound::Order) já virou mensagem do cliente.
    return if message.content_attributes.to_h.key?(Waha::RichNative::Inbound::Order::KEY)

    contact = message.conversation&.contact
    return if contact.nil?

    message.message_type = :incoming
    message.private = false
    message.sender = contact
    message.content = I18n.t(TEXT_KEY, locale: message.account.locale, default: I18n.t(TEXT_KEY))
    message.content_attributes = message.content_attributes.to_h.merge('is_unsupported' => true, 'unsupported_kind' => kind_of(data))
  end

  # O aviso do motor de que uma visualização única do cliente não chegou ao aparelho vinculado (item 11): a main nunca
  # recebe essa mensagem.
  def unavailable_view_once?(data)
    data.is_a?(Hash) && data['from_me'] != true && KINDS[data['content_type'].to_s] == 'view_once'
  end

  def kind_of(data)
    return 'gif' if data['gif'] == true

    KINDS.fetch(data['content_type'].to_s, UNKNOWN_KIND)
  end
end
