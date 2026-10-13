# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1473). O reenvio do Chatwoot regrava
# `content_attributes` vazio; uma mensagem com `rich_message` sairia de novo como texto puro. Aqui ela mantém
# o que tinha (inclusive chaves de outras frentes, como `autonomia_chunk_token`), menos o erro antigo e as marcas
# do transporte da tentativa anterior (WhatsappHybrid::WebTransport e CloudFailureFallback), que o novo envio
# regrava se for o caso.
module RichMessages::RetryKeepsFormat
  PREVIOUS_ATTEMPT_KEYS = %w[external_error whatsapp_transport whatsapp_transport_origin whatsapp_transport_fallback whatsapp_web_id].freeze

  private

  def retry_content_attributes
    return message.content_attributes.except(*PREVIOUS_ATTEMPT_KEYS) if RichMessages.rich?(message)

    super
  end
end
