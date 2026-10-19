# Callback `before_validation` (na criação) de Message (chat#1709, fase 3): guarda, só em memória, o `in_reply_to` que o
# conector mandou junto de uma chave de Waha::RichNative::Inbound. O `before_save` do Chatwoot (`ensure_in_reply_to`)
# apaga o `in_reply_to` que não é da MESMA conversa, e o conector põe a reação ou a edição na conversa que o
# ConversationByContact escolhe (uma nova, quando a original foi resolvida). Sem isto, a reação a uma mensagem da
# conversa anterior virava bolha "Reagiu com" e a IA respondia. Waha::RichNative::Inbound.target_of confere o alvo de
# novo (mesma caixa, mesmo contato).
module Waha::RichNative::Inbound::ReplyTarget
  module_function

  def before_validation(message)
    return unless message.new_record?

    attributes = message.content_attributes.to_h
    return unless Waha::RichNative::Inbound::KEYS.any? { |key| attributes.key?(key) }

    message.instance_variable_set(:@c2y_inbound_reply_to, attributes['in_reply_to'] || attributes[:in_reply_to])
  end

  def target_id(message)
    message.instance_variable_get(:@c2y_inbound_reply_to).presence || message.content_attributes.to_h['in_reply_to']
  end
end
