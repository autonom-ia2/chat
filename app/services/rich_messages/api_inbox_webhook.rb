# Prepend em WebhookListener (chat#1473). A caixa Channel::Api (WhatsApp API/WAHA) não passa pelos serviços de
# envio: quem entrega a mensagem é o webhook da caixa, com o `content` cru. Para mensagem de saída com
# `rich_message`, só esse webhook leva o corpo mais o complemento em texto do tipo. Os webhooks da conta e o
# robô continuam recebendo o `content` original (o hash não é alterado, é copiado).
# Mensagem que não pode sair não é entregue à caixa e fica `failed` com o motivo, como nos outros canais. Essa
# gravação emite um `message_updated`, que volta aqui, acha a mensagem já `failed` e não grava de novo.
# Sem `rich_message` (ou se a mensagem já não existe), a entrega original e mais nada.
module RichMessages::ApiInboxWebhook
  MESSAGE_EVENTS = %w[message_created message_updated].freeze

  private

  def deliver_api_inbox_webhooks(payload, inbox)
    return super unless rich_outgoing_message?(payload) && inbox.channel_type == 'Channel::Api'

    message = Message.find_by(id: payload[:id])
    return super if message.nil?

    error = RichMessages.error_for(message)
    return super(payload.merge(content: RichMessages.text_with_fallback(message, payload[:content])), inbox) if error.nil?

    message.update!(status: :failed, external_error: error) unless message.failed?
  end

  # `payload` é o Message#webhook_data: chaves em símbolo, e `content_attributes` é sempre um hash de chaves em
  # string (vazio quando a coluna está nula).
  def rich_outgoing_message?(payload)
    MESSAGE_EVENTS.include?(payload[:event]) && payload[:content_attributes].key?(RichMessages::KEY) &&
      payload[:message_type] == 'outgoing' && !payload[:private]
  end
end
