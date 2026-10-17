# Prepend em WebhookListener (#1702): atualização só de marca da pele não vai ao webhook da caixa API (o conector WAHA
# reenviaria a mensagem). Os webhooks da conta continuam recebendo. Ver ConversaCanal::AtualizacaoDaPele.
module ConversaCanal::WebhookSemAtualizacaoDaPele
  def message_updated(event)
    return super unless ConversaCanal::AtualizacaoDaPele.so_da_pele?(event.data[:previous_changes])

    message = extract_message_and_account(event)[0]
    return unless message.webhook_sendable?

    deliver_account_webhooks(message.webhook_data.merge(event: 'message_updated'), message.account)
  end
end
