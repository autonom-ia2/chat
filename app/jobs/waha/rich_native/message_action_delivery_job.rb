# O pedido de reação ou de edição feita pelo painel (Waha::RichNative::MessageActions) ao conector do WAHA, pelo webhook
# da caixa (chat#1709, rodada de correção). Antes ia pelo WebhookJob, que engole a falha HTTP: a reação ou a edição
# ficava gravada no chat2you e o painel dizia que deu certo, sem saber se o WhatsApp a recebeu.
# - Falha passageira (sem resposta do motor, 5xx): o job tenta de novo, com espera crescente, ATTEMPTS vezes.
# - Falha que não passa com o tempo (endereço inválido ou recusado, 4xx, caixa sem webhook): direto para o aviso.
# Sem entrega, fica uma nota privada na conversa ("a reação/edição não chegou ao WhatsApp"): a mudança continua gravada
# aqui, à vista, e nada é desfeito em silêncio. `payload` é o evento montado na hora da ação; `delivery_id`, o mesmo em
# todas as tentativas.
class Waha::RichNative::MessageActionDeliveryJob < ApplicationJob
  queue_as :medium
  ATTEMPTS = 5
  NOT_DELIVERED_KEYS = {
    Waha::RichNative::MessageActions::REACTION_EVENT => 'waha.message_actions.reaction_not_delivered',
    Waha::RichNative::MessageActions::EDIT_EVENT => 'waha.message_actions.edit_not_delivered'
  }.freeze

  # O 5xx do motor, para o retry (o 4xx não volta).
  class ServerError < StandardError; end

  retry_on SafeFetch::FetchError, ServerError, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    job.not_delivered!(error)
  end

  def perform(message_id, payload, delivery_id)
    message = Message.find_by(id: message_id)
    return if message.nil?

    url = message.inbox.channel.try(:webhook_url)
    return not_delivered!(:no_webhook_url) if url.blank?

    deliver(message.inbox.channel, payload, delivery_id)
  end

  def deliver(channel, payload, delivery_id)
    Waha::RichNative::MessageActionTrigger.new(channel.webhook_url, payload.deep_symbolize_keys, :api_inbox_webhook,
                                               secret: channel.secret, delivery_id: delivery_id).execute
  rescue SafeFetch::FetchError
    raise
  rescue SafeFetch::HttpError => e
    raise ServerError, "status=#{e.status}" if e.status.to_i >= 500

    not_delivered!(e)
  rescue SafeFetch::Error => e
    not_delivered!(e)
  end

  # Nota privada, no idioma da conta, sem remetente (é o sistema avisando). O erro vai ao log só pela classe.
  def not_delivered!(error)
    message_id, payload, = arguments
    message = Message.find_by(id: message_id)
    key = NOT_DELIVERED_KEYS[payload.to_h.with_indifferent_access[:event]]
    Rails.logger.error("[waha] message action not delivered message=#{message_id} #{error.is_a?(Symbol) ? error : error.class}")
    return if message.nil? || key.nil?

    Messages::MessageBuilder.new(nil, message.conversation, { content: note_text(message.account, key), message_type: 'outgoing',
                                                              private: true }).perform
  end

  private

  def note_text(account, key)
    I18n.t(key, locale: account.locale, default: I18n.t(key))
  end
end
