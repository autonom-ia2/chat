# Prepend em WhatsappHybrid::WebTransport (chat#1709): com a flag `whatsapp_rich_native`, a mensagem rica de tipo
# suportado sai no formato nativo do motor em vez do texto. Todo o resto do envio (sessão, limite, contato, digitando,
# id gerado antes, resultado, erros incertos) continua o do WebTransport: só o pedido final muda.
# Erro do motor no pedido nativo segue as mesmas regras do texto (falha certa ou incerta); não há segunda tentativa
# em texto, para nunca sair duas mensagens.
module WhatsappHybrid::RichNative::Transport
  private

  def deliver(chat_id, physical_id)
    native = WhatsappHybrid::RichNative.payload_for(@message)
    return super if native.nil?

    response = native.deliver(@client, session: session, chat_id: chat_id, id: physical_id)
    WhatsappHybrid::RichNative.mark_sent!(@message, @connection, native_physical_id(native, response, physical_id))
    response
  end

  # A lista não leva o id gerado antes: vale o que o motor devolveu. Sem ele na resposta, fica o gerado (o ack dessa
  # mensagem não vai achá-la, e o log diz).
  def native_physical_id(native, response, physical_id)
    return physical_id if native.pre_generated_id?

    returned = Waha::RichPayload.physical_id(response)
    Rails.logger.warn("[whatsapp_hybrid] rich native without id in response message=#{@message.id}") if returned.nil?
    returned || physical_id
  end
end
