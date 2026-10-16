# Callback `before_create` de Message (chat#1709, fase 2): `waha_native` (o pedido ao motor) nunca é gravado. Ele só
# existe no payload do webhook da caixa (Waha::RichNative::InboxWebhook), montado a partir do `rich_message`. Guardado
# na mensagem, iria ao conector e o motor mandaria o que quem criou quisesse. Sai SEMPRE, venha de onde vier (API de
# mensagens, criação de conversa com mensagem, qualquer outro caminho), com ou sem a flag.
class Waha::RichNative::ContractGuard
  KEY = 'waha_native'.freeze

  def self.before_create(message)
    attributes = message.content_attributes.to_h
    message.content_attributes = attributes.except(KEY) if attributes.key?(KEY)
  end
end
