# frozen_string_literal: true

# #1865 — contato salvo na agenda do aparelho antes de enviar pelo WhatsApp API e lida ao responder, atrás da flag
# `whatsapp_agenda_do_contato`. Por prepend: WebTransport, SendReplyJob e WebhookJob ficam intactos.
Rails.application.config.to_prepare do
  WhatsappHybrid::WebTransport.prepend(WhatsappHybrid::AgendaNoEnvio) unless WhatsappHybrid::WebTransport <= WhatsappHybrid::AgendaNoEnvio
  SendReplyJob.prepend(ConversaCanal::LeituraAoResponder) unless SendReplyJob <= ConversaCanal::LeituraAoResponder
  WebhookJob.prepend(Waha::AgendaNoWebhook) unless WebhookJob <= Waha::AgendaNoWebhook
end
