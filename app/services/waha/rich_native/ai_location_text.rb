# O texto que a IA lê de uma localização do cliente na caixa WAHA comum (chat#1709, revisão da rodada 2). Com a flag
# `whatsapp_rich_native`, a localização vira o cartão de mapa da API oficial: `content` nil, `shared_location` e o
# anexo `location` (Waha::RichNative::Inbound::Location). O histórico e a pergunta da IA Autonomia leem só o `content`
# (Waha::RichNative::ResponderLocation): sem este texto, ela receberia uma mensagem vazia do cliente e responderia a ela.
# Monta "Localização compartilhada pelo cliente: <nome, endereço>. Mapa: <link>" (e o aviso da localização ao vivo) a
# partir dos números gravados, sem regex. Fora da caixa WAHA comum, sem a flag, com `content` ou sem `shared_location`:
# nil, e nada muda.
module Waha::RichNative::AiLocationText
  KEY = 'shared_location'.freeze
  MAP_URL = 'https://www.google.com/maps/search/?api=1&query='.freeze

  module_function

  def for(message)
    return if message.nil? || message.content.to_s.strip.present?

    shared = message.content_attributes.to_h[KEY]
    return unless shared.is_a?(Hash) && coordinates?(shared)
    return unless Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative.enabled?(message.account)

    text(message.account, shared)
  end

  def coordinates?(shared)
    [shared['latitude'], shared['longitude']].all?(Numeric)
  end

  def text(account, shared)
    coordinates = "#{shared['latitude']},#{shared['longitude']}"
    place = [shared['name'], shared['address']].compact_blank.join(', ').presence || coordinates
    key = shared['live'] == true ? 'waha.ai.live_location' : 'waha.ai.location'
    I18n.t(key, place: place, url: "#{MAP_URL}#{coordinates}", locale: account.locale,
                default: I18n.t(key, place: place, url: "#{MAP_URL}#{coordinates}"))
  end
end
