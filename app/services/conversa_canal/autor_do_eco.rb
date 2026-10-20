# Prepend em Whatsapp::IncomingMessageBaseService (#1941, item 3). Mensagem que o atendente manda pelo app do celular
# volta como eco (`external_echo`, sem remetente: na Cloud com coexistência e na caixa híbrida, que recebe pela Cloud).
# O eco grava quem estava atribuído à conversa NA HORA em que chegou, em `c2y_phone_author_id` (ou null, sem
# atribuição). A tela mostra esse nome em cima do balão; reatribuir depois não muda as antigas.
# Contrato com o WhatsApp Híbrido: a mesma chave vale no WAHA comum, gravada pelo conector de lá.
module ConversaCanal::AutorDoEco
  CHAVE = :c2y_phone_author_id

  private

  def message_content_attributes(message)
    attrs = super
    return attrs unless outgoing_echo

    attrs.merge(CHAVE => @conversation&.assignee_id)
  end
end
