# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1473). O reenvio do Chatwoot regrava
# `content_attributes` vazio; uma mensagem com `rich_message` sairia de novo como texto puro. Aqui ela mantém
# o que tinha (inclusive chaves de outras frentes, como `autonomia_chunk_token`), menos o erro antigo e as marcas
# do transporte da tentativa anterior (as do WhatsApp Híbrido começam com `whatsapp_transport`), que o novo
# envio regrava se for o caso.
module RichMessages::RetryKeepsFormat
  PREVIOUS_ATTEMPT_KEYS = %w[external_error whatsapp_web_id].freeze
  PREVIOUS_TRANSPORT_PREFIX = 'whatsapp_transport'.freeze

  private

  def retry_content_attributes
    return super unless RichMessages.rich?(message)

    message.content_attributes.reject { |key, _| PREVIOUS_ATTEMPT_KEYS.include?(key) || key.start_with?(PREVIOUS_TRANSPORT_PREFIX) }
  end
end
