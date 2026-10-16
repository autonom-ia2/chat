# "Documento" do "+" da conversa (#1702): manda o anexo como documento, mesmo sendo foto ou vídeo, como no WhatsApp.
# O painel diz quais anexos (pela posição em `attachments`) vão assim, em `document_indexes`: documento e foto no
# mesmo envio saem cada um com o seu tipo. Só vale em caixa de WhatsApp (oficial ou WAHA). Nos outros canais o pedido
# é ignorado: lá o tipo "arquivo" muda o envio (Instagram e Facebook mandam como arquivo; o LINE descarta).
module ConversaCanal::ComoDocumento
  # :file quando o anexo dessa posição vai como documento; nil para seguir o tipo de sempre.
  def self.tipo(params, inbox, posicao)
    pedidos = Array(params[:document_indexes]).filter_map { |valor| Integer(valor, exception: false) }
    return unless pedidos.include?(posicao) && whatsapp?(inbox.channel)

    :file
  end

  def self.whatsapp?(canal)
    canal.is_a?(Channel::Whatsapp) || (canal.is_a?(Channel::Api) && canal.waha_provider?)
  end
end
