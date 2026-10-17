# O texto que a IA lê de uma localização do cliente na caixa WAHA comum (chat#1709). Com a flag `whatsapp_rich_native`,
# a localização vira o cartão de mapa da API oficial: `content` nil (ou a legenda da localização ao vivo),
# `shared_location` e o anexo `location` (Waha::RichNative::Inbound::Location). O histórico e a pergunta da IA Autonomia
# leem o `content` (Waha::RichNative::ResponderLocation): sem este texto, ela receberia uma mensagem vazia do cliente.
# Decisão do Rodrigo (17/10/2026): SÓ nome e endereço, sem latitude, longitude nem link de mapa, no formato do #1753
# ("Localização: nome — endereço"; sem nenhum dos dois, "Localização (sem nome nem endereço)"). A localização ao vivo
# usa o mesmo texto; a legenda do cliente, quando há, vem antes (ResponderLocation). Quando o #1753
# (Autonomia::Agents::Operate::ResumoDaMensagemRica) estiver na main, o ResponderLocation passa a usá-lo: fica para o
# merge. Fora da caixa WAHA comum, sem a flag ou sem `shared_location`: nil, e nada muda.
module Waha::RichNative::AiLocationText
  KEY = 'shared_location'.freeze
  LABEL = 'Localização'.freeze
  UNNAMED = 'Localização (sem nome nem endereço)'.freeze
  SEPARATOR = ' — '.freeze

  module_function

  def for(message)
    return if message.nil?

    shared = message.content_attributes.to_h[KEY]
    return unless shared.is_a?(Hash)
    return unless Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative.enabled?(message.account)

    text(shared)
  end

  def text(shared)
    parts = [line(shared['name']), line(shared['address'])].compact_blank
    parts.empty? ? UNNAMED : "#{LABEL}: #{parts.join(SEPARATOR)}"
  end

  # Texto numa linha só; o que não é texto conta como ausente.
  def line(value)
    value.split.join(' ') if value.is_a?(String)
  end
end
