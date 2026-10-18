# frozen_string_literal: true

# #1702 — a reação do cliente no WhatsApp vira o selo na mensagem reagida, como no app, em vez de ser descartada.
# Prepend no recebimento; o serviço do Chatwoot fica intacto. Ver app/services/whatsapp/incoming_reaction_extension.rb.
Rails.application.config.to_prepare do
  unless Whatsapp::IncomingMessageBaseService <= Whatsapp::IncomingReactionExtension
    Whatsapp::IncomingMessageBaseService.prepend(Whatsapp::IncomingReactionExtension)
  end
end
