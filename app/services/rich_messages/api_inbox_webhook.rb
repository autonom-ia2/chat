# Prepend em WebhookListener (chat#1473). A caixa Channel::Api (WhatsApp API/WAHA) não passa pelos serviços de
# envio: quem entrega a mensagem é o webhook da caixa, com o `content` cru. Para mensagem com `rich_message` que
# vai ao canal, só esse webhook leva o corpo mais a versão em texto do tipo. Os webhooks da conta e o robô
# continuam recebendo o `content` original (o hash não é alterado, é copiado).
# Mensagem que não pode sair não é entregue à caixa e, se de fato iria ao webhook dela, fica `failed` com o
# motivo, como nos outros canais. Essa gravação emite um `message_updated`, que volta aqui, acha a mensagem já
# `failed` e não grava de novo.
# Nenhum erro daqui sobe ao dispatcher, para não tirar o evento dos outros listeners: vai ao rastreador de erros
# e ao log, e a mensagem NÃO é entregue à caixa. Entregar o `content` cru mandaria ao cliente o corpo sem o
# link, em silêncio; sem entrega, a mensagem fica parada e o erro aparece no rastreador.
# Pelo mesmo motivo, mensagem com `rich_message` apagada entre o evento e a entrega não é entregue à caixa.
# Sem `rich_message`, a entrega original e mais nada.
module RichMessages::ApiInboxWebhook
  MESSAGE_EVENTS = %w[message_created message_updated].freeze

  private

  def deliver_api_inbox_webhooks(payload, inbox)
    return super unless rich_message_payload?(payload) && inbox.channel_type == 'Channel::Api'

    inbox_payload = rich_inbox_payload(payload, inbox)
    super(inbox_payload, inbox) if inbox_payload
  end

  # `payload` é o Message#webhook_data: chaves em símbolo, e `content_attributes` é sempre um hash de chaves em
  # string (vazio quando a coluna está nula).
  def rich_message_payload?(payload)
    MESSAGE_EVENTS.include?(payload[:event]) && payload[:content_attributes].key?(RichMessages::KEY)
  end

  # O que entregar ao webhook da caixa; nil quando a mensagem não pode sair.
  def rich_inbox_payload(payload, inbox)
    message = Message.find_by(id: payload[:id])
    return nil unless message
    return payload unless RichMessages.goes_to_channel?(message)

    error = RichMessages.error_for(message)
    return payload.merge(content: RichMessages.text_with_fallback(message, payload[:content])) if error.nil?

    RichMessages.fail!(message, error) if !message.failed? && reaches_inbox_webhook?(payload, inbox)
    nil
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: inbox.account).capture_exception
    Rails.logger.error("[rich_messages] api_inbox_webhook message=#{payload[:id]} #{e.class}")
    nil
  end

  # As mesmas saídas antecipadas do método original: sem endereço de webhook ou destino de transmissão bloqueado.
  def reaches_inbox_webhook?(payload, inbox)
    inbox.channel.webhook_url.present? && !autonomia_blocked_api_broadcast_payload?(payload)
  end
end
