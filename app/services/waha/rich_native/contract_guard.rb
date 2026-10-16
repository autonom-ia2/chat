# Callback `before_create` de Message (chat#1709, fases 2 e 3): as chaves do pedido ao conector do WAHA nunca são
# gravadas. Elas só existem no payload do webhook da caixa, montadas pelo chat2you:
# - `waha_native` (Waha::RichNative::InboxWebhook): o envio nativo, montado a partir do `rich_message`;
# - `waha_text` e `waha_media_as_media` (Waha::RichNative::OutgoingHints): o texto já no formato do WhatsApp e o pedido
#   de mandar foto e vídeo como mídia.
# Guardadas na mensagem, iriam ao conector e o motor mandaria o que quem criou quisesse. Saem SEMPRE, venha de onde
# vier (API de mensagens, criação de conversa com mensagem, qualquer outro caminho), com ou sem a flag.
class Waha::RichNative::ContractGuard
  KEYS = %w[waha_native waha_text waha_media_as_media].freeze

  def self.before_create(message)
    attributes = message.content_attributes.to_h
    message.content_attributes = attributes.except(*KEYS) if KEYS.any? { |key| attributes.key?(key) }
  end
end
