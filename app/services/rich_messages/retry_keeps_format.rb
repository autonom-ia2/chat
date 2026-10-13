# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1473). O reenvio do Chatwoot regrava
# `content_attributes` vazio; uma mensagem com `rich_message` sairia de novo como texto puro. Aqui ela mantém
# tudo o que tinha (inclusive chaves de outras frentes, como `autonomia_chunk_token`); o erro antigo já foi
# limpo pelo Messages::StatusUpdateService, na linha anterior do reenvio.
module RichMessages::RetryKeepsFormat
  private

  def retry_content_attributes
    return message.content_attributes if message.content_attributes[RichMessages::KEY].present?

    super
  end
end
