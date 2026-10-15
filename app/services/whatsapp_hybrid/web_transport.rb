# Envia uma mensagem da caixa Cloud pela sessão WAHA auxiliar (chat#1067).
# O id físico é gerado ANTES do envio e gravado no source_id: quando o eco da Meta chegar (2 a 7 s
# depois, às vezes antes da resposta do WAHA), a conciliação já encontra a mensagem.
class WhatsappHybrid::WebTransport
  THROTTLE_RETRY = 15.seconds
  # Teto das novas tentativas do limite por minuto do plano B do 131047 (20 × 15 s = 5 min); depois falha de forma certa
  # e a campanha pode mandar o modelo (#1453). As demais mensagens esperam sem teto, como sempre.
  THROTTLE_MAX_RETRIES = 20
  THROTTLED_OUT_ERROR = 'O WhatsApp API ficou no limite de envios por minuto e a mensagem não saiu. Reenvie mais tarde ' \
                        'ou use um modelo aprovado.'.freeze
  CHAT_ID_TTL = 1.day.to_i
  # Estado da sessão mais velho que isto é revalidado no motor antes de enviar.
  STATUS_MAX_AGE = 60.seconds
  DISCONNECTED_ERROR = 'O WhatsApp API deste número está desconectado. Reconecte na aba WhatsApp API da caixa ' \
                       'ou use um modelo aprovado.'.freeze
  MEDIA_ENDPOINTS = { 'image' => 'sendImage', 'audio' => 'sendVoice', 'video' => 'sendVideo' }.freeze

  MESSAGE_KEY_TTL = 7.days.to_i

  # Resultado estável do envio, em content_attributes (chat#1349). Quem decide reenviar por outro caminho lê isto, nunca o texto do erro:
  #   accepted  - o motor aceitou o envio (não é entrega: a confirmação vem depois, pelo ack);
  #   failed    - falha certa, nada saiu (sessão caída, contato sem WhatsApp, erro do motor, limite de conversas novas);
  #   uncertain - o motor não respondeu: pode ter saído, nunca reenviar sozinho;
  #   throttled - passou do limite por minuto, espera a próxima tentativa (resultado ainda não é final).
  OUTCOME_KEY = 'whatsapp_transport_outcome'.freeze
  UNCONFIRMED_ERROR = 'O WhatsApp API não confirmou o envio. Confira no celular antes de reenviar.'.freeze
  # #1453: sem resposta do motor ANTES do pedido de envio (estado da sessão, consulta do contato): nada saiu.
  NO_ANSWER_ERROR = 'O WhatsApp API não respondeu e a mensagem não saiu. Verifique a conexão na aba WhatsApp API da caixa.'.freeze
  THROTTLE_ENQUEUE_ERROR = 'Não foi possível agendar a nova tentativa pelo WhatsApp API. Reenvie a mensagem.'.freeze
  CAPPED_ERROR = 'O WhatsApp limitou conversas novas neste número por enquanto. Use um modelo aprovado ' \
                 'ou tente de novo depois do fim do ciclo (aba WhatsApp API da caixa).'.freeze

  # Mensagem enviada pelo WhatsApp API a partir do id físico (para as confirmações de entrega do motor).
  def self.message_for(connection, physical_id)
    message_id = ::Redis::Alfred.get(message_key(connection, physical_id))
    Message.find_by(id: message_id, inbox_id: connection.inbox_id) if message_id.present?
  end

  def self.message_key(connection, physical_id)
    "whatsapp_hybrid:msg:#{connection.id}:#{physical_id}"
  end

  def initialize(message:, connection:, origin:, client: Waha::Client.new)
    @message = message
    @connection = connection
    @origin = origin
    @client = client
  end

  def perform
    return fail!(DISCONNECTED_ERROR, 'disconnected') unless session_working?
    return throttle! if WhatsappHybrid::RateLimit.new(@connection, @origin).exceeded?

    chat_id = resolve_chat_id
    return fail!('O número deste contato não tem WhatsApp ativo.') if chat_id.blank?

    send_now(chat_id)
  rescue Waha::Client::Timeout
    # Sem resposta ao pedido de envio não sabemos se saiu: nunca reenviar automaticamente. Antes dele (#1453), nada saiu.
    @delivering ? fail!(UNCONFIRMED_ERROR, 'uncertain') : fail!(NO_ANSWER_ERROR)
  rescue Waha::Client::Error => e
    Rails.logger.error("[whatsapp_hybrid] send failed message=#{@message.id}: #{e.message.to_s[0, 200]}")
    return reach_out_refused! if WhatsappHybrid::ReachOut.engine_refusal?(e)

    # O erro pode ser a sessão caída: atualiza o estado para o roteador parar de escolher o Web.
    session_manager.refresh!(sync_proxy: false)
    fail!(engine_error_text(e))
  end

  private

  def session
    @connection.session_name
  end

  def session_manager
    @session_manager ||= WhatsappHybrid::SessionManager.new(@connection, client: @client)
  end

  # Revalida no motor quando o estado gravado é velho; celular desconectado deixa de ser escolhido na hora.
  def session_working?
    session_manager.refresh!(sync_proxy: false) if @connection.status_checked_at.nil? || @connection.status_checked_at < STATUS_MAX_AGE.ago
    @connection.status == 'connected' && @connection.same_number?
  end

  def send_now(chat_id)
    physical_id = @client.new_message_id(session)
    mark_pending!(physical_id)
    WhatsappHybrid::Typing.new(@client, session: session, chat_id: chat_id).simulate(@message)
    @delivering = true
    deliver_or_uncertain(chat_id, physical_id)
    record_outcome!('accepted')
    RichMessages.mark_sent_as_text!(@message)
    log('sent', physical_id)
  end

  # #1453: depois que o pedido de envio saiu, erro do servidor (5xx), conexão fechada ou resposta ilegível não provam que nada saiu. Viram
  # Timeout (resultado `uncertain`), para ninguém reenviar por cima. Recusa do WhatsApp (463, 475) e 4xx seguem como falha.
  def deliver_or_uncertain(chat_id, physical_id)
    deliver(chat_id, physical_id)
  rescue Errno::ECONNRESET, Errno::EPIPE, Errno::ETIMEDOUT, IOError, Net::WriteTimeout => e
    raise Waha::Client::Timeout, "WAHA envio sem confirmação: conexão fechada (#{e.class})"
  rescue Errno::EHOSTUNREACH, Errno::ENETUNREACH => e
    # Sem rota até o motor: o pedido não chegou, nada saiu.
    raise Waha::Client::Error, "WAHA envio sem rota (#{e.class})"
  rescue Waha::Client::InvalidResponse => e
    raise Waha::Client::Timeout, e.message
  rescue Waha::Client::Error => e
    raise if e.is_a?(Waha::Client::Timeout) || e.status.to_i < 500 || engine_refused?(e)

    # Só lê o estado da sessão (não reenvia): com a sessão caída, o roteador para de escolher o Web.
    session_manager.refresh!(sync_proxy: false)
    raise Waha::Client::Timeout.new(e.message, status: e.status)
  end

  def engine_refused?(error)
    WhatsappHybrid::ReachOut.engine_refusal?(error) || error.message.to_s.include?('error 475')
  end

  def deliver(chat_id, physical_id)
    attachment = @message.attachments.first
    return @client.send_text(session: session, chat_id: chat_id, text: @message.outgoing_content.to_s, id: physical_id) if attachment.nil?

    kind = MEDIA_ENDPOINTS.fetch(attachment.file_type.to_s, 'sendFile')
    file = { url: attachment.download_url, mimetype: attachment.file.content_type, filename: attachment.file.filename.to_s }
    caption = kind == 'sendVoice' ? nil : @message.outgoing_content
    @client.send_media(kind, session: session, chat_id: chat_id, id: physical_id, media: { file: file, caption: caption })
  end

  def mark_pending!(physical_id)
    merge_attributes!({ 'whatsapp_transport' => 'web', 'whatsapp_transport_origin' => @origin }, source_id: physical_id)
    ::Redis::Alfred.setex(self.class.message_key(@connection, physical_id), @message.id, MESSAGE_KEY_TTL)
  end

  def resolve_chat_id
    phone = @message.conversation.contact.phone_number.to_s.delete('^0-9')
    key = "whatsapp_hybrid:chat_id:#{session}:#{phone}"
    cached = ::Redis::Alfred.get(key)
    return cached if cached.present?

    result = @client.check_contact_exists(phone: phone, session: session)
    chat_id = result['numberExists'] ? result['chatId'] : nil
    ::Redis::Alfred.setex(key, chat_id, CHAT_ID_TTL) if chat_id.present?
    chat_id
  end

  # O WhatsApp devolve o erro 475 quando o número atingiu o limite de conversas novas do ciclo.
  def engine_error_text(error)
    return CAPPED_ERROR if error.message.to_s.include?('error 475')

    'Não foi possível enviar pelo WhatsApp API. Verifique a conexão na aba WhatsApp API da caixa.'
  end

  # Erro 463 (chat#1486): o WhatsApp recusou conversa nova com este contato. Bloqueia o contato por 6 h e falha sem
  # reenviar; o retrato do limite é atualizado num job à parte, sem consulta ao motor dentro do envio.
  def reach_out_refused!
    WhatsappHybrid::ReachOut.new(@connection, @message.conversation.contact).block!
    fail!(WhatsappHybrid::ReachOut::BLOCKED_ERROR)
    WhatsappHybrid::TimelockRefreshJob.perform_later(@connection.id)
  end

  # Passou do limite por minuto: a mensagem espera a próxima janela em vez de sair em rajada.
  def throttle!
    return fail!(THROTTLED_OUT_ERROR) if cloud_fallback? && throttle_count > THROTTLE_MAX_RETRIES

    # #1453: agenda ANTES de gravar `throttled`; sem a nova tentativa na fila, a mensagem não fica esperando à toa.
    return fail!(THROTTLE_ENQUEUE_ERROR) unless enqueue_retry

    log('throttled') if record_outcome!('throttled')
  end

  def enqueue_retry
    job = retry_job.set(wait: THROTTLE_RETRY).perform_later(@message.id)
    job.present? && job.successfully_enqueued?
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] retry not enqueued message=#{@message.id}: #{e.class}")
    false
  end

  # #1453: a mensagem do plano B do 131047 tem o source_id da Meta, e o SendReplyJob a ignoraria.
  def retry_job
    cloud_fallback? ? WhatsappHybrid::FallbackRetryJob : SendReplyJob
  end

  # Mensagem que o plano B do 131047 (CloudFailureFallback) assumiu.
  def cloud_fallback?
    @message.content_attributes.to_h['whatsapp_transport_fallback'].present?
  end

  FINAL_OUTCOMES = %w[accepted failed uncertain].freeze

  # #1453: `throttled` nunca sobrescreve resultado final (uma nova tentativa em voo depois de a campanha fechar a
  # mensagem). Devolve false quando não gravou.
  def record_outcome!(value)
    @message.with_lock do
      attributes = @message.content_attributes.to_h
      next false if value == 'throttled' && FINAL_OUTCOMES.include?(attributes[OUTCOME_KEY])

      @message.update!(content_attributes: attributes.merge(OUTCOME_KEY => value))
    end
  end

  # O eco da Meta (2 a 7 s depois do envio, às vezes antes da resposta do WAHA) e a marca de mensagem rica escrevem o
  # mesmo content_attributes (chat#1555). Grava sobre o registro relido sob trava e acrescenta só as chaves de quem chama:
  # nunca devolve o hash lido antes do envio.
  def merge_attributes!(extra, columns = {})
    @message.with_lock do
      @message.update!(columns.merge(content_attributes: @message.content_attributes.to_h.merge(extra)))
    end
  end

  def fail!(reason, outcome = 'failed')
    # external_error mora dentro de content_attributes: grava junto, senão um sobrescreve o outro.
    merge_attributes!({ 'whatsapp_transport' => 'web', 'whatsapp_transport_origin' => @origin, 'external_error' => reason,
                        OUTCOME_KEY => outcome == 'uncertain' ? 'uncertain' : 'failed' }, status: :failed)
    log(outcome)
    campaign_fallback_after_failure unless outcome == 'uncertain'
  end

  # #1453: texto de campanha que este transporte assumiu no 131047 e não saiu (falha certa, inclusive depois do throttled,
  # na nova tentativa do SendReplyJob): a campanha manda o modelo, uma vez só (trava na entrega). Nunca derruba o envio.
  def campaign_fallback_after_failure
    CampaignJourney::ConversaAberta::QuedaHibrido.after_transport_failure(@message)
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] queda da campanha não pedida message=#{@message.id}: #{e.class}")
  end

  # Quantas vezes esta mensagem esperou o limite por minuto (expira junto com a chave da mensagem).
  def throttle_count
    key = "whatsapp_hybrid:throttle:#{@message.id}"
    count = ::Redis::Alfred.incr(key)
    ::Redis::Alfred.expire(key, MESSAGE_KEY_TTL) if count == 1
    count
  end

  def log(outcome, physical_id = nil)
    WhatsappHybrid::Stats.record(@connection, origin: @origin, outcome: outcome)
    Rails.logger.info(
      "[whatsapp_hybrid] route=web outcome=#{outcome} origin=#{@origin} inbox=#{@connection.inbox_id} " \
      "message=#{@message.id} physical_id=#{physical_id}"
    )
  end
end
