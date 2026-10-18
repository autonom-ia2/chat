# Prepend em Whatsapp::IncomingMessageBaseService (#1702). A Cloud API e o 360dialog mandam a figurinha com
# `type: "sticker"`, mas o Chatwoot grava como foto (`file_content_type` junta image e sticker) e a marca se perde.
# Aqui o anexo continua `image` (nada muda para quem já lê foto) e ganha `meta.is_sticker = true`, sem coluna nova.
# O WhatsApp Híbrido recebe pela conexão oficial, então passa por aqui também. A caixa WAHA não passa: o app de
# Chatwoot do WAHA entrega só o arquivo .webp pela API da caixa, sem dizer que era figurinha.
module ConversaCanal::FigurinhaRecebida
  TIPO = 'sticker'.freeze
  CHAVE = 'is_sticker'.freeze

  private

  def attach_files
    attachment = super
    return attachment unless message_type == TIPO && attachment.is_a?(Attachment) && ConversaCanal::Pele.ligada?(inbox.account)

    attachment.meta = (attachment.meta || {}).merge(CHAVE => true)
    attachment
  end
end
