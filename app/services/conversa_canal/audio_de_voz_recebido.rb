# Prepend em Whatsapp::IncomingMessageBaseService (#1702). A Cloud API diz no próprio áudio se ele é nota de voz
# gravada no app (`audio.voice: true`) ou um arquivo de áudio (`false`):
# https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/audio
# O Chatwoot descarta o campo. Aqui ele vira `meta.is_voice_message` no anexo, a mesma marca que o painel já grava no
# áudio gravado por nós (Messages::MessageBuilder) e que o WhatsApp Híbrido grava na caixa WAHA (#1709). A tela
# desenha a nota de voz ou o arquivo (fone) a partir dela. Sem `voice` no aviso, nada é gravado (a tela não adivinha).
module ConversaCanal::AudioDeVozRecebido
  TIPO = 'audio'.freeze
  CHAVE = 'is_voice_message'.freeze

  private

  def attach_files
    attachment = super
    return attachment unless message_type == TIPO && attachment.is_a?(Attachment) && ConversaCanal::Pele.ligada?(inbox.account)

    voz = messages_data.first.dig(TIPO, 'voice')
    return attachment unless [true, false].include?(voz)

    attachment.meta = (attachment.meta || {}).merge(CHAVE => voz)
    attachment
  end
end
