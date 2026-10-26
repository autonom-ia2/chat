# frozen_string_literal: true

# #2202 (PR 0): resposta nossa marca a conversa como vista. Ver app/services/conversa_canal/vista_ao_responder.rb.
# O eco da Cloud guarda a hora em que saiu do celular (app/services/conversa_canal/hora_do_eco.rb).
Rails.application.config.to_prepare do
  Message.prepend(ConversaCanal::VistaAoResponder) unless Message <= ConversaCanal::VistaAoResponder
  Whatsapp::IncomingMessageBaseService.prepend(ConversaCanal::HoraDoEco) unless Whatsapp::IncomingMessageBaseService <= ConversaCanal::HoraDoEco
end
