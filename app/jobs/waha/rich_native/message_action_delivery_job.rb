# O pedido de reação ou de edição feita pelo painel (Waha::RichNative::MessageActions) ao conector do WAHA, pelo webhook
# da caixa (chat#1709, rodada de correção). Antes ia pelo WebhookJob, que engole a falha HTTP: a reação ou a edição
# ficava gravada no chat2you e o painel dizia que deu certo, sem saber se o WhatsApp a recebeu.
# Aqui a falha (sem resposta, recusa, 5xx) levanta e o job tenta de novo, com espera crescente, ATTEMPTS vezes. Esgotado,
# fica uma nota privada na conversa ("a reação/edição não chegou ao WhatsApp"): a mudança continua gravada aqui, à
# vista, e nada é desfeito em silêncio. `payload` é o evento montado na hora da ação; `delivery_id`, o mesmo em todas as
# tentativas.
class Waha::RichNative::MessageActionDeliveryJob < ApplicationJob
  queue_as :medium
  ATTEMPTS = 5
  NOT_DELIVERED_KEYS = {
    Waha::RichNative::MessageActions::REACTION_EVENT => 'waha.message_actions.reaction_not_delivered',
    Waha::RichNative::MessageActions::EDIT_EVENT => 'waha.message_actions.edit_not_delivered'
  }.freeze

  retry_on SafeFetch::Error, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    job.not_delivered!(error)
  end

  def perform(message_id, payload, delivery_id)
    message = Message.find_by(id: message_id)
    channel = message&.inbox&.channel
    return if channel.nil? || channel.webhook_url.blank?

    Waha::RichNative::MessageActionTrigger.new(channel.webhook_url, payload.deep_symbolize_keys, :api_inbox_webhook,
                                               secret: channel.secret, delivery_id: delivery_id).execute
  end

  # Nota privada, no idioma da conta, sem remetente (é o sistema avisando). O erro vai ao log só pela classe.
  def not_delivered!(error)
    message_id, payload, = arguments
    message = Message.find_by(id: message_id)
    key = NOT_DELIVERED_KEYS[payload.to_h.with_indifferent_access[:event]]
    Rails.logger.error("[waha] message action not delivered message=#{message_id} #{error.class}")
    return if message.nil? || key.nil?

    Messages::MessageBuilder.new(nil, message.conversation, { content: note_text(message.account, key), message_type: 'outgoing',
                                                              private: true }).perform
  end

  private

  def note_text(account, key)
    I18n.t(key, locale: account.locale, default: I18n.t(key))
  end
end
