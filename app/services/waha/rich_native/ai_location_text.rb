# O texto que a IA lê de uma localização do cliente na caixa WAHA comum (chat#1709). Com a flag `whatsapp_rich_native`,
# a localização vira o cartão de mapa da API oficial: `content` nil (ou a legenda da localização ao vivo),
# `shared_location` e o anexo `location` (Waha::RichNative::Inbound::Location). O histórico e a pergunta da IA Autonomia
# leem o `content` (Waha::RichNative::ResponderLocation): sem este texto, ela receberia uma mensagem vazia do cliente.
# Decisão do Rodrigo (17/10/2026): SÓ nome e endereço, sem latitude, longitude nem link de mapa. O formato é o do #1753,
# e a regra é uma só: Autonomia::Agents::Operate::ResumoDaMensagemRica.localizacao ("Localização: nome — endereço"; sem
# nenhum dos dois, "Localização (sem nome nem endereço)"). A localização ao vivo usa o mesmo texto; a legenda do
# cliente, quando há, vem antes (ResponderLocation). Fora da caixa WAHA comum, sem a flag ou sem `shared_location`:
# nil, e nada muda.
module Waha::RichNative::AiLocationText
  KEY = 'shared_location'.freeze
  RESUMO = Autonomia::Agents::Operate::ResumoDaMensagemRica

  module_function

  def for(message)
    return if message.nil?

    shared = message.content_attributes.to_h[KEY]
    return unless shared.is_a?(Hash)
    return unless Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative.enabled?(message.account)

    text(shared)
  end

  def text(shared)
    RESUMO.localizacao(shared)
  end
end
