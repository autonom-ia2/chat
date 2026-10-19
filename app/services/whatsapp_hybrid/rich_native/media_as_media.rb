# Prepend em WhatsappHybrid::WebTransport (chat#1709, fase 3): no plano B do Híbrido, foto fora de JPG/PNG sai como foto,
# e não sai como arquivo nem fica sem prévia. Com a flag `whatsapp_rich_native`, só durante o envio desta mensagem, o
# cliente do motor troca por WhatsappHybrid::RichNative::MediaClient:
# - GIF vai por `sendVideo` (o motor converte em vídeo, como o WhatsApp faz com GIF);
# - as outras (webp, bmp, tiff, heic, avif...) vão por `sendImage` com uma variante JPEG do ActiveStorage.
# Vídeo já sai convertido (`convert: true` do Waha::Client); nada muda nele. Sem a flag, os pedidos de antes.
module WhatsappHybrid::RichNative::MediaAsMedia
  private

  def deliver(chat_id, physical_id)
    attachment = @message.attachments.first
    return super unless WhatsappHybrid::RichNative::MediaClient.rewrite?(attachment) && Waha::RichNative.enabled?(@message.account)

    original = @client
    @client = WhatsappHybrid::RichNative::MediaClient.new(original, attachment)
    begin
      super
    ensure
      @client = original
    end
  end
end
