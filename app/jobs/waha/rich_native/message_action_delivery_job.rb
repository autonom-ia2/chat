# O pedido de reação ou de edição feita pelo painel (Waha::RichNative::MessageActions) ao conector do WAHA, pelo webhook
# da caixa (chat#1709, rodada de correção). Antes ia pelo WebhookJob, que engole a falha HTTP: a reação ou a edição
# ficava gravada no chat2you e o painel dizia que deu certo, sem saber se o WhatsApp a recebeu.
# - Falha passageira (sem resposta do motor, 5xx): o job tenta de novo, com espera crescente, ATTEMPTS vezes.
# - Falha que não passa com o tempo (endereço inválido ou recusado, 4xx, caixa sem webhook): direto para o aviso.
# Sem entrega, fica uma nota privada na conversa ("a reação/edição não chegou ao WhatsApp"): a mudança continua gravada
# aqui, à vista, e nada é desfeito em silêncio.
# O evento é montado NA HORA DA ENTREGA, do estado atual da mensagem: a reação da empresa que está gravada agora (vazia =
# remover) e o texto atual. Montado na hora da ação, uma tentativa refeita depois de um 503 levava o estado velho por
# cima do novo (o conector recebia ❤️ e depois 👍; o painel ficava com ❤️ e o cliente com 👍). A ação mais nova da
# mesma mensagem (reação ou edição) supera as anteriores: só ela entrega (o registro `latest_key` guarda o
# `delivery_id` dela), e como manda o estado atual, o último estado sempre chega, também depois de falha passageira.
class Waha::RichNative::MessageActionDeliveryJob < ApplicationJob
  queue_as :medium
  ATTEMPTS = 5
  NOT_DELIVERED_KEYS = {
    Waha::RichNative::MessageActions::REACTION_EVENT => 'waha.message_actions.reaction_not_delivered',
    Waha::RichNative::MessageActions::EDIT_EVENT => 'waha.message_actions.edit_not_delivered'
  }.freeze

  # O 5xx do motor, para o retry (o 4xx não volta).
  class ServerError < StandardError; end

  # Cobre as tentativas do job com folga (espera polinomial).
  LATEST_TTL = 1.day.to_i

  retry_on SafeFetch::FetchError, ServerError, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    job.not_delivered!(error)
  end

  # A ação do painel pede a entrega: esta passa a ser a mais nova daquela mensagem e daquele tipo.
  # Com o Redis fora, enfileira sem a marca: a mudança já está gravada no banco, e o job manda o estado atual (enviar de
  # novo o mesmo estado não faz mal). O painel não recebe 500 por isso.
  def self.request!(message, event)
    delivery_id = SecureRandom.uuid
    begin
      ::Redis::Alfred.setex(latest_key(message.id, event), delivery_id, LATEST_TTL)
    rescue Redis::BaseError => e
      Rails.logger.error("[waha] message action latest mark not saved message=#{message.id} #{e.class}")
    end
    perform_later(message.id, event, delivery_id)
  end

  def self.latest_key(message_id, event)
    "waha:message_action:latest:#{event}:#{message_id}"
  end

  def perform(message_id, event, delivery_id)
    message = Message.find_by(id: message_id)
    return if message.nil? || superseded?(message_id, event, delivery_id)

    url = message.inbox.channel.try(:webhook_url)
    return not_delivered!(:no_webhook_url) if url.blank?

    deliver(message, event, payload_for(message, event), delivery_id)
  end

  # O evento com o estado de agora.
  def payload_for(message, event)
    extra = if event == Waha::RichNative::MessageActions::REACTION_EVENT
              { c2y_reaction: { emoji: business_emoji(message) } }
            else
              { c2y_edit: { waha_text: Waha::RichNative::OutgoingHints.whatsapp_text(message.content.to_s, message) } }
            end
    JSON.parse(message.webhook_data.merge(event: event, **extra).to_json)
  end

  # O estado foi lido do banco; uma ação mais nova pode ter chegado nesse meio tempo: confere de novo logo antes do HTTP.
  def deliver(message, event, payload, delivery_id)
    return if superseded?(message.id, event, delivery_id)

    channel = message.inbox.channel
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
    message_id, event, delivery_id = arguments
    # A ação já foi superada por uma mais nova, que entrega (ou avisa) por conta própria: sem nota falsa.
    return if superseded?(message_id, event, delivery_id)

    Rails.logger.error("[waha] message action not delivered message=#{message_id} #{error.is_a?(Symbol) ? error : error.class}")
    self.class.note_not_delivered!(Message.find_by(id: message_id), event)
  end

  # A nota privada "a reação/edição não chegou ao WhatsApp". Também quando o pedido nem sai (caixa sem webhook, trava de
  # transmissão: Waha::RichNative::MessageActions.deliver): o atendente nunca fica com um sucesso calado.
  def self.note_not_delivered!(message, event)
    key = NOT_DELIVERED_KEYS[event]
    return if message.nil? || key.nil?

    text = I18n.t(key, locale: message.account.locale, default: I18n.t(key))
    Messages::MessageBuilder.new(nil, message.conversation, { content: text, message_type: 'outgoing', private: true }).perform
  end

  private

  # Uma ação mais nova da mesma mensagem e tipo já pediu a entrega: ela manda o estado atual.
  # Redis fora: não superada (melhor mandar o estado atual de novo que perder a entrega ou o aviso).
  def superseded?(message_id, event, delivery_id)
    latest = ::Redis::Alfred.get(self.class.latest_key(message_id, event))
    latest.present? && latest != delivery_id
  rescue Redis::BaseError => e
    Rails.logger.error("[waha] message action latest mark not read message=#{message_id} #{e.class}")
    false
  end

  # A reação da empresa gravada agora ('' quando não há: remover).
  def business_emoji(message)
    reaction = Array(message.content_attributes.to_h[Waha::RichNative::Reactions::KEY]).find do |entry|
      entry.is_a?(Hash) && entry['sender_type'] == Waha::RichNative::Reactions::USER_TYPE
    end
    reaction&.dig('emoji').to_s
  end
end
