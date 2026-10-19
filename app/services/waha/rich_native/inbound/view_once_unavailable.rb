# `waha_view_once_unavailable` (chat#1709, decisão do Rodrigo de 16/10/2026): o cliente mandou uma mensagem de
# visualização única, e o WhatsApp não manda a chave da mídia ao aparelho vinculado. O conector cria uma mensagem do
# cliente com { from_me: false, id }. Com a flag, ela fica visível como mensagem do cliente com o aviso do WhatsApp Web
# (waha.view_once_unavailable, no idioma da conta) e `view_once_unavailable: true` para a tela (balão cinza em itálico,
# com o "1" num círculo). `view_once_id` guarda o id para, se a mídia de verdade chegar depois
# (Waha::RichNative::Inbound::ViewOnceResolved), o aviso sair. A IA não responde nem lê o aviso
# (Waha::RichNative::AgentTurnGuard). Sem a flag: atividade escondida (Waha::RichNative::Inbound#apply_without_flag),
# como se não existisse, que é o que a main vê. Só a do CLIENTE (`from_me` false explícito).
module Waha::RichNative::Inbound::ViewOnceUnavailable
  KEY = 'view_once_unavailable'.freeze
  ID_KEY = 'view_once_id'.freeze
  TEXT_KEY = 'waha.view_once_unavailable'.freeze

  module_function

  def apply(message, data)
    return unless customer?(data)

    contact = message.conversation&.contact
    return if contact.nil?

    message.message_type = :incoming
    message.private = false
    message.sender = contact
    message.content = I18n.t(TEXT_KEY, locale: message.account.locale, default: I18n.t(TEXT_KEY))
    message.content_attributes = message.content_attributes.to_h.merge({ KEY => true, ID_KEY => data['id'].presence&.to_s }.compact)
  end

  def customer?(data)
    data.is_a?(Hash) && data['from_me'] == false
  end

  def notice?(message)
    message.content_attributes.to_h[KEY] == true
  end
end
