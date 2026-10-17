# `waha_media_failed` (chat#1709, rodada 2): a mídia que o motor não conseguiu baixar nem depois de tentar de novo,
# { kind, mimetype, filename, caption, reason }. Na main fica uma nota privada (o cliente parece ignorado e a IA não
# vê) ou um texto com aviso. Com a flag vira mensagem VISÍVEL do cliente: a legenda, ou uma linha neutra, sem voz de
# comando ("Foto não recebida (o download falhou)", waha.media_unavailable.<kind>), com `media_unavailable` { kind,
# reason, at, has_caption } para a bolha (sem legenda, o `content` é o aviso do servidor), que mostra à equipe o aviso
# "não foi possível baixar, peça para reenviar".
# É turno do cliente para o agente de IA (decisão: o cliente mandou algo e espera resposta): a IA lê o aviso como a
# fala dele ("Foto não recebida (o download falhou)") e responde a ele, o que naturalmente é pedir o reenvio. Com
# legenda, lê a legenda.
# Só a nota do CLIENTE, pelo `from_me` que o conector (c2y-rich-3b) manda sempre: `false` explícito. A direção da
# mensagem não serve: toda nota privada do conector sai OUTGOING, inclusive a do cliente (base.ts, "Private notes can
# only be sent as outgoing messages"). `from_me` true ou ausente (conector antigo): fica como a main.
module Waha::RichNative::Inbound::MediaFailed
  KEY = 'media_unavailable'.freeze
  KINDS = %w[voice audio image video document sticker].freeze
  DEFAULT_KIND = 'document'.freeze

  module_function

  def apply(message, data)
    return unless customer_note?(data)

    contact = message.conversation&.contact
    return if contact.nil?

    kind = KINDS.include?(data['kind']) ? data['kind'] : DEFAULT_KIND
    message.message_type = :incoming
    message.private = false
    message.sender = contact
    caption = data['caption'].presence
    message.content = caption || notice(message.account, kind)
    message.content_attributes = message.content_attributes.to_h.merge(
      KEY => { 'kind' => kind, 'reason' => 'download_failed', 'at' => Time.current.iso8601, 'has_caption' => caption.present? }
    )
  end

  def customer_note?(data)
    data.is_a?(Hash) && data['from_me'] == false
  end

  def notice(account, kind)
    key = "waha.media_unavailable.#{kind}"
    I18n.t(key, locale: account.locale, default: I18n.t(key))
  end
end
