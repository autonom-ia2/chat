# `waha_media_failed` (chat#1709, rodada 2): a mídia que o motor não conseguiu baixar nem depois de tentar de novo,
# { kind, mimetype, filename, caption, reason }. Na main fica uma nota privada (o cliente parece ignorado e a IA não
# vê) ou um texto com aviso. Com a flag vira mensagem VISÍVEL do cliente: a legenda, ou o aviso "não foi possível
# baixar, peça para reenviar" (waha.media_unavailable.<kind>), com `media_unavailable` { kind, reason, at } para a
# bolha. Mídia mandada pelo celular da empresa (from_me) fica como a main.
module Waha::RichNative::Inbound::MediaFailed
  KEY = 'media_unavailable'.freeze
  KINDS = %w[voice audio image video document sticker].freeze
  DEFAULT_KIND = 'document'.freeze

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && data['from_me'] != true

    contact = message.conversation&.contact
    return if contact.nil?

    kind = KINDS.include?(data['kind']) ? data['kind'] : DEFAULT_KIND
    message.message_type = :incoming
    message.private = false
    message.sender = contact
    message.content = data['caption'].presence || notice(message.account, kind)
    message.content_attributes = message.content_attributes.to_h.merge(
      KEY => { 'kind' => kind, 'reason' => 'download_failed', 'at' => Time.current.iso8601 }
    )
  end

  def notice(account, kind)
    key = "waha.media_unavailable.#{kind}"
    I18n.t(key, locale: account.locale, default: I18n.t(key))
  end
end
