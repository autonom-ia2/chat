# Envia uma mensagem da caixa Cloud pela sessão WAHA auxiliar (chat#1067).
# O id físico é gerado ANTES do envio e gravado no source_id: quando o eco da Meta chegar (2 a 7 s
# depois, às vezes antes da resposta do WAHA), a conciliação já encontra a mensagem.
class WhatsappHybrid::WebTransport
  THROTTLE_RETRY = 15.seconds
  CHAT_ID_TTL = 1.day.to_i
  # Estado da sessão mais velho que isto é revalidado no motor antes de enviar.
  STATUS_MAX_AGE = 60.seconds
  DISCONNECTED_ERROR = 'O WhatsApp API deste número está desconectado. Reconecte na aba WhatsApp API da caixa ' \
                       'ou use um modelo aprovado.'.freeze
  MEDIA_ENDPOINTS = { 'image' => 'sendImage', 'audio' => 'sendVoice', 'video' => 'sendVideo' }.freeze

  MESSAGE_KEY_TTL = 7.days.to_i
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

    physical_id = @client.new_message_id(session)
    mark_pending!(physical_id)
    deliver(chat_id, physical_id)
    log('sent', physical_id)
  rescue Waha::Client::Timeout
    # Sem resposta não sabemos se saiu: nunca reenviar automaticamente.
    fail!('O WhatsApp API não confirmou o envio. Confira no celular antes de reenviar.', 'uncertain')
  rescue Waha::Client::Error => e
    Rails.logger.error("[whatsapp_hybrid] send failed message=#{@message.id}: #{e.message.to_s[0, 200]}")
    # O erro pode ser a sessão caída: atualiza o estado para o roteador parar de escolher o Web.
    session_manager.refresh!
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
    session_manager.refresh! if @connection.status_checked_at.nil? || @connection.status_checked_at < STATUS_MAX_AGE.ago
    @connection.status == 'connected' && @connection.same_number?
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
    attrs = @message.content_attributes.to_h.merge('whatsapp_transport' => 'web', 'whatsapp_transport_origin' => @origin)
    @message.update!(source_id: physical_id, content_attributes: attrs)
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

  # Passou do limite por minuto: a mensagem espera a próxima janela em vez de sair em rajada.
  def throttle!
    SendReplyJob.set(wait: THROTTLE_RETRY).perform_later(@message.id)
    log('throttled')
  end

  def fail!(reason, outcome = 'failed')
    # external_error mora dentro de content_attributes: grava junto, senão um sobrescreve o outro.
    attrs = @message.content_attributes.to_h.merge(
      'whatsapp_transport' => 'web', 'whatsapp_transport_origin' => @origin, 'external_error' => reason
    )
    @message.update!(status: :failed, content_attributes: attrs)
    log(outcome)
  end

  def log(outcome, physical_id = nil)
    WhatsappHybrid::Stats.record(@connection, origin: @origin, outcome: outcome)
    Rails.logger.info(
      "[whatsapp_hybrid] route=web outcome=#{outcome} origin=#{@origin} inbox=#{@connection.inbox_id} " \
      "message=#{@message.id} physical_id=#{physical_id}"
    )
  end
end
