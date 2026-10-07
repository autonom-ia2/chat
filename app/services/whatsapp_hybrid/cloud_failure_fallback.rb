# Prepend em Whatsapp::IncomingMessageBaseService (chat#1067): plano B seguro.
# A Meta só devolve o erro 131047 ("mais de 24 horas desde a última resposta do cliente") quando NÃO
# entregou a mensagem. Esse é o único caso em que reenviar pelo WhatsApp API não duplica nada.
# Qualquer outra falha (ou falha sem código) fica como está: sem certeza, sem reenvio.
module WhatsappHybrid::CloudFailureFallback
  WINDOW_CLOSED_CODE = 131_047

  private

  def update_message_with_status(message, status)
    super
    retry_through_web(message) if window_closed_failure?(status)
  end

  def window_closed_failure?(status)
    status[:status] == 'failed' && Array(status[:errors]).any? { |error| error[:code].to_i == WINDOW_CLOSED_CODE }
  end

  def retry_through_web(message)
    router = fallback_router(message.reload)
    return if router.nil?

    failed_attrs = message.content_attributes.to_h
    message.update!(status: :sent, content_attributes: failed_attrs.except('external_error').merge('whatsapp_transport_fallback' => true))
    WhatsappHybrid::WebTransport.new(message: message, connection: router.connection, origin: router.origin_of(message)).perform
  rescue StandardError
    # Erro fora do motor (Redis, banco): a mensagem volta para a falha original, nunca fica "enviada" sem ter saído.
    message.update!(status: :failed, content_attributes: failed_attrs) if failed_attrs
    raise
  end

  # Roteador quando a mensagem pode ir pelo WhatsApp API; nil quando não pode.
  def fallback_router(message)
    return unless message.failed? && message.outgoing?
    return unless WhatsappHybrid::Config.account_allowed?(message.account_id)

    router = WhatsappHybrid::Router.new(message.conversation)
    router if router.web_ready? && router.web_allowed_for?(message)
  end
end
