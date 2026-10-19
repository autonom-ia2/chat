# #1865 — prepend em WebhookJob: o webhook da caixa API (`api_inbox_webhook`) passa antes pelo Waha::AntesDoEnvio. O
# WebhookJob e o WebhookListener do Chatwoot ficam intactos; os demais tipos de webhook não mudam.
module Waha::AgendaNoWebhook
  API_INBOX = 'api_inbox_webhook'.freeze

  def perform(url, payload, webhook_type = :account_webhook, secret: nil, delivery_id: nil)
    Waha::AntesDoEnvio.para_payload(payload) if webhook_type.to_s == API_INBOX
    super
  end
end
