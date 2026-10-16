# Prepend em WhatsappHybrid::WebTransport (chat#1709): com a flag `whatsapp_rich_native`, a mensagem rica de tipo
# suportado sai no formato nativo do motor em vez do texto. Todo o resto do envio (sessão, limite, contato, digitando,
# id gerado antes, resultado, erros incertos) continua o do WebTransport: só o pedido final muda.
# - Recusa explícita do motor (4xx, 501; nunca 463/475): nada saiu, então vai o texto de sempre, UMA vez, pelo caminho
#   original (que grava a marca 'text').
# - 5xx, conexão fechada, sem resposta ou resposta ilegível: pode ter saído. Segue a regra do texto (incerto), sem
#   texto por cima.
module WhatsappHybrid::RichNative::Transport
  private

  def deliver(chat_id, physical_id)
    native = WhatsappHybrid::RichNative.payload_for(@message)
    return super if native.nil?

    Waha::RichNative.write_source_id!(@message, Waha::RichNative.pending_source_id(@message)) unless native.pre_generated_id?
    response = deliver_native(native, chat_id, physical_id)
    return restore_text_source_id(physical_id) && super if response == :refused

    WhatsappHybrid::RichNative.mark_sent!(@message, @connection, native_physical_id(native, response, physical_id))
    response
  end

  # Antes do texto da recusa: o `source_id` volta ao id gerado, que é o que o texto leva ao motor (o ack procura por ele).
  def restore_text_source_id(physical_id)
    Waha::RichNative.write_source_id!(@message, physical_id) if @message.source_id != physical_id
    true
  end

  def deliver_native(native, chat_id, physical_id)
    native.deliver(@client, session: session, chat_id: chat_id, id: physical_id)
  rescue Waha::Client::Error => e
    raise unless WhatsappHybrid::RichNative.nothing_sent?(e)

    Rails.logger.warn("[whatsapp_hybrid] rich native refused status=#{e.status} message=#{@message.id}: sending text")
    :refused
  end

  # A lista não leva o id gerado antes: vale o que o motor devolveu. Sem ele na resposta, fica o `source_id` provisório
  # (o ack dessa mensagem não vai achá-la; a Meta não ecoa lista, então não há duplicata), e o log diz.
  def native_physical_id(native, response, physical_id)
    return physical_id if native.pre_generated_id?

    returned = Waha::RichPayload.physical_id(response)
    log_missing_id(response) if returned.nil?
    returned
  end

  def log_missing_id(response)
    Rails.logger.warn("[whatsapp_hybrid] rich native without id in response message=#{@message.id} response=#{response.class}")
  end
end
