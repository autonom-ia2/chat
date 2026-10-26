# frozen_string_literal: true

# #2202 (PR 0): resposta de pessoa marca a conversa como vista. Ver app/services/conversa_canal/vista_ao_responder.rb.
Rails.application.config.to_prepare do
  Message.prepend(ConversaCanal::VistaAoResponder) unless Message <= ConversaCanal::VistaAoResponder
end
