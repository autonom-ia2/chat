# Fecha o resultado do envio pelo WhatsApp API depois de um erro inesperado no meio do caminho (Redis, banco, fila), para
# a mensagem nunca ficar "enviada" sem ter saído nem ser reenviada por cima (#1453). Decide pelo que já aconteceu:
# - accepted: o motor aceitou; a mensagem fica como está;
# - failed ou uncertain: já fechado; só a mensagem volta a `failed`, com o erro que já tinha;
# - throttled, ou envio ainda não marcado (pending/sem resultado e sem whatsapp_transport = web): o pedido ao motor não
#   saiu, então `failed`, com o erro dado (o original da Meta, no plano B do 131047);
# - envio marcado (whatsapp_transport = web) e sem resultado final: o pedido pode ter saído, então `uncertain`, com o
#   aviso de conferir no celular.
# Devolve o resultado final. Usado pelo plano B do 131047 (CloudFailureFallback), pela nova tentativa dele e pela
# conferência da campanha.
module WhatsappHybrid::UnexpectedErrorOutcome
  module_function

  OUTCOME_KEY = WhatsappHybrid::WebTransport::OUTCOME_KEY

  # only_from: fecha só se, DENTRO da trava, o resultado ainda for um destes (a conferência decide por uma leitura feita
  # antes; outro processo pode ter mudado). Senão devolve o resultado atual, sem gravar nada.
  def settle!(message, external_error: nil, only_from: nil)
    message.with_lock do
      attributes = message.content_attributes.to_h
      next attributes[OUTCOME_KEY] if only_from&.exclude?(attributes[OUTCOME_KEY])
      next 'accepted' if attributes[OUTCOME_KEY] == 'accepted'

      outcome = final_outcome(attributes)
      # Sem validação: a trava de rajada da mensagem não pode impedir o registro de um envio que já aconteceu.
      closed = attributes.merge(OUTCOME_KEY => outcome, 'external_error' => error_text(attributes, outcome, external_error))
      message.assign_attributes(status: :failed, content_attributes: closed)
      message.save!(validate: false)
      outcome
    end
  end

  def final_outcome(attributes)
    current = attributes[OUTCOME_KEY]
    return current if %w[failed uncertain].include?(current)
    return 'uncertain' if attributes['whatsapp_transport'] == 'web'

    'failed'
  end

  def error_text(attributes, outcome, external_error)
    return attributes['external_error'] if %w[failed uncertain].include?(attributes[OUTCOME_KEY])
    return WhatsappHybrid::WebTransport::UNCONFIRMED_ERROR if outcome == 'uncertain'

    external_error || attributes['external_error']
  end
end
