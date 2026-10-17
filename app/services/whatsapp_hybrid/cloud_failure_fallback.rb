# Prepend em Whatsapp::IncomingMessageBaseService (chat#1067): plano B seguro.
# A Meta só devolve o erro 131047 ("mais de 24 horas desde a última resposta do cliente") quando NÃO
# entregou a mensagem. Esse é o único caso em que reenviar pelo WhatsApp API não duplica nada.
# Qualquer outra falha (ou falha sem código) fica como está: sem certeza, sem reenvio.
module WhatsappHybrid::CloudFailureFallback
  WINDOW_CLOSED_CODE = 131_047

  private

  def update_message_with_status(message, status)
    # #1453: aviso 131047 repetido de mensagem que o plano B já assumiu (ainda `pending` ou `throttled`) não volta a
    # gravar a falha da Meta por cima do envio em curso. Pular o `super` aqui é o caminho mais curto: o resultado do
    # WhatsApp API segue sendo a única fonte, e nada muda para os outros avisos.
    return if window_closed_failure?(status) && already_taken?(message)

    super
    retry_through_web(message) if window_closed_failure?(status)
  end

  def window_closed_failure?(status)
    status[:status] == 'failed' && Array(status[:errors]).any? { |error| error[:code].to_i == WINDOW_CLOSED_CODE }
  end

  def retry_through_web(message)
    router, failed_attrs = take_over(message)
    return if router.nil?

    WhatsappHybrid::Stats.record(router.connection, origin: router.origin_of(message), outcome: 'fallback')
    WhatsappHybrid::WebTransport.new(message: message, connection: router.connection, origin: router.origin_of(message)).perform
  rescue StandardError
    # Erro fora do motor (Redis, banco): nunca fica "enviada" sem ter saído. #1453: a marca e o que o WebTransport já
    # gravou ficam, e o resultado fecha pelo que aconteceu (WhatsappHybrid::UnexpectedErrorOutcome): se o pedido ao motor
    # pode ter saído, a campanha não manda o modelo por cima, nem o próximo aviso reenvia.
    WhatsappHybrid::UnexpectedErrorOutcome.settle!(message, external_error: failed_attrs['external_error']) if failed_attrs
    raise
  end

  # #1453: confere e marca sob trava. Dois avisos 131047 do mesmo wamid (simultâneos ou não) nunca reenviam duas vezes.
  # O roteador (Redis, leituras) é decidido antes, fora da trava.
  def take_over(message)
    # #1453: se a campanha já mandou o modelo para este texto (erro antes da marca, e um aviso repetido), não sai o
    # texto depois do modelo.
    return [nil, nil] if already_taken?(message.reload) || CampaignJourney::ConversaAberta::QuedaHibrido.template_sent?(message)

    router = fallback_router(message)
    return [nil, nil] if router.nil?

    message.with_lock do
      next [nil, nil] if already_taken?(message) || !message.failed?

      failed_attrs = message.content_attributes.to_h
      # `pending` (#1453): o plano B assumiu e ainda não há resultado. Quem lê nesse meio tempo (outro aviso, a campanha)
      # nunca reenvia nem manda o modelo por cima.
      message.update!(status: :sent, content_attributes: failed_attrs.except('external_error')
                                                                     .merge('whatsapp_transport_fallback' => true,
                                                                            WhatsappHybrid::WebTransport::OUTCOME_KEY => 'pending'))
      [router, failed_attrs]
    end
  end

  # #1453: um segundo aviso 131047 do mesmo wamid não refaz o envio que o WhatsApp API já assumiu.
  def already_taken?(message)
    message.content_attributes.to_h['whatsapp_transport_fallback'].present?
  end

  # Roteador quando a mensagem pode ir pelo WhatsApp API; nil quando não pode.
  def fallback_router(message)
    return unless message.failed? && message.outgoing?
    return unless WhatsappHybrid::Config.account_allowed?(message.account_id)

    router = WhatsappHybrid::Router.new(message.conversation)
    # Contato barrado pelo limite de conversas novas do WhatsApp (chat#1486) fica com a falha original.
    router if router.web_ready? && router.web_allowed_for?(message) && router.reach_out.allowed?
  end
end
