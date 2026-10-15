# Fecha o resultado do envio pelo WhatsApp API depois de um erro inesperado no meio do caminho (Redis, banco, fila), para
# a mensagem nunca ficar "enviada" sem ter saído nem ser reenviada por cima (#1453). Decide pelo que já aconteceu:
# - accepted: o motor aceitou; a mensagem fica como está;
# - failed ou uncertain: já fechado; só a mensagem volta a `failed`;
# - throttled, ou envio ainda não marcado: o pedido ao motor não saiu, então `failed`;
# - envio marcado (whatsapp_transport = web) e sem resultado: o pedido pode ter saído, então `uncertain`.
# Devolve o resultado final. Usado pelo plano B do 131047 (CloudFailureFallback) e pela nova tentativa dele.
module WhatsappHybrid::UnexpectedErrorOutcome
  module_function

  def settle!(message, external_error: nil)
    message.with_lock do
      attributes = message.content_attributes.to_h
      next 'accepted' if attributes[WhatsappHybrid::WebTransport::OUTCOME_KEY] == 'accepted'

      outcome = final_outcome(attributes)
      message.update!(status: :failed, content_attributes: { 'external_error' => external_error }.compact
                                                                                     .merge(attributes)
                                                                                     .merge(WhatsappHybrid::WebTransport::OUTCOME_KEY => outcome))
      outcome
    end
  end

  def final_outcome(attributes)
    current = attributes[WhatsappHybrid::WebTransport::OUTCOME_KEY]
    return current if %w[failed uncertain].include?(current)
    return 'uncertain' if current.nil? && attributes['whatsapp_transport'] == 'web'

    'failed'
  end
end
