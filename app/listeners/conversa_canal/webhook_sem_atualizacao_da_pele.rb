# Prepend em WebhookListener (#1702): atualização só de marca da pele não vai ao webhook da caixa WAHA (o conector
# reenviaria a mensagem). Caixa API de integração própria do cliente continua recebendo tudo, como na main. Os
# webhooks da conta continuam recebendo. Ver ConversaCanal::AtualizacaoDaPele.
module ConversaCanal::WebhookSemAtualizacaoDaPele
  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return super unless caixa_waha?(message) && ConversaCanal::AtualizacaoDaPele.silenciar?(message, event.data[:previous_changes])
    return unless message.webhook_sendable?

    deliver_account_webhooks(message.webhook_data.merge(event: 'message_updated'), message.account)
  end

  private

  def caixa_waha?(message)
    canal = message&.inbox&.channel
    canal.is_a?(Channel::Api) && canal.waha_provider?
  end
end
