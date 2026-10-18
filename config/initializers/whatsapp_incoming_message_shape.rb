# frozen_string_literal: true

# chat#1816 — campo da Cloud API que chega como texto no lugar do objeto não derruba o recebimento.
# Ver app/services/whatsapp/incoming_message_shape_extension.rb.
Rails.application.config.to_prepare do
  unless Whatsapp::IncomingMessageBaseService <= Whatsapp::IncomingMessageShapeExtension
    Whatsapp::IncomingMessageBaseService.prepend(Whatsapp::IncomingMessageShapeExtension)
  end
end
