# Prepend em WhatsappHybrid::WebTransport (chat#1709): com a flag `whatsapp_rich_native`, a mensagem rica de tipo
# suportado sai no formato nativo do motor em vez do texto. Todo o resto do envio (sessão, limite, contato, digitando,
# id gerado antes, resultado, erros incertos) continua o do WebTransport: só o pedido final muda.
# - Recusa explícita do motor (4xx, 501; nunca 463/475): nada saiu, então vai o texto de sempre, UMA vez, pelo caminho
#   original (que grava a marca 'text').
# - 5xx, conexão fechada, sem resposta ou resposta ilegível: pode ter saído. Segue a regra do texto (incerto), sem
#   texto por cima.
module WhatsappHybrid::RichNative::Transport
  RESTORE_FAILED = 'A mensagem não saiu: o WhatsApp API recusou o formato e o texto não pôde ser enviado. Reenvie a mensagem.'.freeze
  # Sinais (catch/throw, não exceção) que fecham o envio já marcado como falha: nenhum `rescue` do WebTransport os
  # reclassifica, e o `perform` termina sem regravar o resultado nem o motivo. `deliver` é o dono de CLOSED; ele passa
  # o fechamento ao `perform` (PERFORM_CLOSED). `perform` é a ÚNICA entrada: `deliver` chamado fora dele levanta
  # ClosedOutsidePerform depois de a mensagem já estar `failed`, em vez de deixar um throw sem dono.
  CLOSED = :whatsapp_hybrid_rich_native_closed
  PERFORM_CLOSED = :whatsapp_hybrid_rich_native_perform_closed

  class ClosedOutsidePerform < StandardError; end

  def perform
    @rich_native_performing = true
    catch(PERFORM_CLOSED) { super }
  ensure
    @rich_native_performing = false
  end

  private

  def deliver(chat_id, physical_id)
    native = WhatsappHybrid::RichNative.payload_for(@message)
    return super if native.nil?

    closed = true
    as_text = false
    response = catch(CLOSED) do
      Waha::RichNative.write_source_id!(@message, Waha::RichNative.pending_source_id(@message)) unless native.pre_generated_id?
      sent = deliver_native(native, chat_id, physical_id)
      as_text = sent == :refused
      sent = restore_text_source_id(physical_id) && super if as_text
      closed = false
      sent
    end
    return hand_closed_send! if closed
    return response if as_text

    WhatsappHybrid::RichNative.mark_sent!(@message, @connection, native_physical_id(native, response, physical_id))
    response
  end

  def hand_closed_send!
    throw PERFORM_CLOSED if @rich_native_performing

    raise ClosedOutsidePerform, "message=#{@message.id}: envio fechado como falha fora do perform"
  end

  # Antes do texto da recusa: o `source_id` volta ao id gerado, que é o que o texto leva ao motor (o ack procura por ele).
  # Se não der para gravar, nada saiu (a recusa foi explícita e o texto não foi pedido): a mensagem fica `failed` com
  # RESTORE_FAILED e resultado 'failed', o erro vai ao tracker, e o envio fecha pelo sinal CLOSED (sem passar pelos
  # `rescue` do WebTransport, que regravariam o motivo). A campanha recebe a queda, como em toda falha certa: com o
  # resultado 'failed', ela manda o modelo (CampaignJourney::ConversaAberta::QuedaHibrido).
  # Se nem o `failed` gravar (banco fora), não fecha em silêncio: relança o erro original, e o job falha à vista
  # (Sidekiq e tracker). O `source_id` provisório impede o reenvio pelo motor: não há duplicata.
  def restore_text_source_id(physical_id)
    Waha::RichNative.write_source_id!(@message, physical_id) if @message.source_id != physical_id
    true
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @message.account).capture_exception
    close_as_failed!(e)
    throw CLOSED
  end

  def close_as_failed!(original)
    write_failed_or_raise!(original)
    refresh_session
    log('failed')
    campaign_fallback_after_failure
  end

  def write_failed_or_raise!(original)
    write_failed!
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] rich native fail not saved message=#{@message.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: @message.account).capture_exception
    raise original
  end

  # Como o WebTransport faz depois de um erro do motor: relê o estado da sessão (sem gravar proxy), para o roteador parar
  # de escolher o WhatsApp API se ela caiu. Só leitura; erro aqui não muda o resultado já gravado.
  def refresh_session
    session_manager.refresh!(sync_proxy: false)
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_hybrid] rich native session refresh failed message=#{@message.id} #{e.class}")
  end

  # Sem as validações do modelo (a de rajada recusaria numa conversa movimentada).
  def write_failed!
    failed = { 'whatsapp_transport' => 'web', 'whatsapp_transport_origin' => @origin, 'external_error' => RESTORE_FAILED,
               WhatsappHybrid::WebTransport::OUTCOME_KEY => 'failed' }
    @message.with_lock do
      @message.status = :failed
      @message.content_attributes = @message.content_attributes.to_h.merge(failed)
      @message.save!(validate: false)
    end
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
