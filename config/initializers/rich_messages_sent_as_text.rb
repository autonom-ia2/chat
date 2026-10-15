# frozen_string_literal: true

# chat#1555 — A mensagem rica que sai como texto guarda isso e o texto enviado. Na caixa API a marca entra na
# criação, antes do webhook. Initializer próprio, fora de config/initializers/rich_messages.rb.
# Ver RichMessages.mark_sent_as_text! e RichMessages::ApiInboxSentAsText.
Rails.application.config.to_prepare do
  if Message._create_callbacks.none? { |callback| callback.filter == RichMessages::ApiInboxSentAsText }
    Message.before_create RichMessages::ApiInboxSentAsText
  end
end
