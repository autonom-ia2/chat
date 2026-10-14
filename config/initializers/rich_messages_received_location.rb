# frozen_string_literal: true

# chat#1473 (P5) — A localização recebida do cliente fica estruturada para o robô e o agente.
# Prepend próprio, fora de config/initializers/rich_messages.rb. Ver RichMessages::ReceivedLocation.
Rails.application.config.to_prepare do
  unless Whatsapp::IncomingMessageBaseService <= RichMessages::ReceivedLocation
    Whatsapp::IncomingMessageBaseService.prepend(RichMessages::ReceivedLocation)
  end
end
