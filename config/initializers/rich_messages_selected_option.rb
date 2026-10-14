# frozen_string_literal: true

# chat#1473 (P3) — a resposta do cliente a um botão ou a uma lista guarda o `id` da opção tocada
# (`content_attributes.selected_option`). Prepend no ponto mais estreito do recebimento do WhatsApp, a montagem de
# `content_attributes`; o serviço do Chatwoot fica intacto. Ver app/services/rich_messages/selected_option.rb.
Rails.application.config.to_prepare do
  unless Whatsapp::IncomingMessageBaseService <= RichMessages::SelectedOption
    Whatsapp::IncomingMessageBaseService.prepend(RichMessages::SelectedOption)
  end
end
