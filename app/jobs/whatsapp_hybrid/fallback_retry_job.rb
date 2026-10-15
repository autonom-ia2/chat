# Nova tentativa do reenvio pelo WhatsApp API que o plano B do 131047 (WhatsappHybrid::CloudFailureFallback) assumiu e que
# ficou no limite por minuto (#1453). O SendReplyJob não serve aqui: a mensagem já tem o source_id da Meta, e o envio do
# Chatwoot ignora mensagem com source_id (Base::SendOnChannelService#outgoing_message_originated_from_channel?). Sem esta
# fila, a mensagem ficava `throttled` (e "enviada" na tela) para sempre, sem sair.
class WhatsappHybrid::FallbackRetryJob < ApplicationJob
  queue_as :high

  OUTCOME_KEY = WhatsappHybrid::WebTransport::OUTCOME_KEY
  UNAVAILABLE_ERROR = 'O WhatsApp API deixou de estar disponível para esta mensagem enquanto ela esperava. Reenvie ou use ' \
                      'um modelo aprovado.'.freeze

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.nil? || !claim(message)

    router = WhatsappHybrid::Router.new(message.conversation)
    return settle(message, UNAVAILABLE_ERROR) unless still_allowed?(message, router)

    WhatsappHybrid::WebTransport.new(message: message, connection: router.connection, origin: router.origin_of(message)).perform
  rescue StandardError
    # Erro fora do motor: o resultado fecha pelo que já aconteceu, nunca fica "enviada" sem ter saído.
    settle(message) if message
    raise
  end

  private

  # Só quem ainda espera, e só um job por vez: o `throttled` é trocado por `pending` sob trava. Um job repetido, ou
  # outro resultado já gravado, não reenvia; quem lê `pending` (a campanha) nunca manda o modelo por cima.
  def claim(message)
    message.with_lock do
      next false unless message.content_attributes.to_h[OUTCOME_KEY] == 'throttled'

      message.update!(content_attributes: message.content_attributes.to_h.merge(OUTCOME_KEY => 'pending'))
    end
  end

  # As mesmas condições do plano B, conferidas de novo: a rota, a conta ou o contato podem ter mudado durante a espera.
  def still_allowed?(message, router)
    WhatsappHybrid::Config.account_allowed?(message.account_id) && router.web_ready? && router.web_allowed_for?(message) &&
      router.reach_out.allowed?
  end

  # Falha certa (nada saiu): a campanha, se o texto for dela, manda o modelo uma vez.
  def settle(message, external_error = nil)
    outcome = WhatsappHybrid::UnexpectedErrorOutcome.settle!(message, external_error: external_error)
    Rails.logger.info("[whatsapp_hybrid] fallback retry encerrado message=#{message.id} outcome=#{outcome}")
    CampaignJourney::ConversaAberta::QuedaHibrido.after_transport_failure(message) if outcome == 'failed'
  end
end
