# "Documento" do "+" da conversa (#1702): manda o anexo como documento, mesmo sendo foto ou vídeo, como no WhatsApp.
# Só vale em caixa de WhatsApp (oficial ou WAHA). Nos outros canais o pedido é ignorado: lá o tipo "arquivo" muda o
# envio (Instagram e Facebook mandam como arquivo; o LINE descarta).
module ConversaCanal::ComoDocumento
  def self.pedido?(params, inbox)
    return false unless ActiveModel::Type::Boolean.new.cast(params[:send_as_document])

    canal = inbox.channel
    canal.is_a?(Channel::Whatsapp) || (canal.is_a?(Channel::Api) && canal.waha_provider?)
  end
end
