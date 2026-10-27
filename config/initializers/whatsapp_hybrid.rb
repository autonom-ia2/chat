# frozen_string_literal: true

# chat#1067 — WhatsApp Híbrido: a caixa Cloud usa uma sessão WAHA auxiliar como segundo transporte.
# Tudo no fork por prepend; os serviços do Chatwoot ficam intactos. Ver docs/whatsapp-hibrido-cloud-waha-prd.md.
Rails.application.config.to_prepare do
  Conversation.prepend(WhatsappHybrid::ConversationExtension) unless Conversation <= WhatsappHybrid::ConversationExtension
  unless Whatsapp::SendOnWhatsappService <= WhatsappHybrid::SendOnWhatsappExtension
    Whatsapp::SendOnWhatsappService.prepend(WhatsappHybrid::SendOnWhatsappExtension)
  end
  unless Whatsapp::IncomingMessageBaseService <= WhatsappHybrid::EchoReconcilerExtension
    Whatsapp::IncomingMessageBaseService.prepend(WhatsappHybrid::EchoReconcilerExtension)
  end
  unless Whatsapp::IncomingMessageBaseService <= WhatsappHybrid::CloudFailureFallback
    Whatsapp::IncomingMessageBaseService.prepend(WhatsappHybrid::CloudFailureFallback)
  end
  # chat#1489: a bolha "não suportada" guarda o tipo e o código da Meta e, com a flag, é recuperada pelo aparelho.
  unless Whatsapp::IncomingMessageBaseService <= WhatsappHybrid::UnsupportedMessageExtension
    Whatsapp::IncomingMessageBaseService.prepend(WhatsappHybrid::UnsupportedMessageExtension)
  end
  # #2246: a recebida guarda o id físico, para a leitura feita no celular encontrá-la.
  unless Whatsapp::IncomingMessageBaseService <= WhatsappHybrid::RecebidaIndexada
    Whatsapp::IncomingMessageBaseService.prepend(WhatsappHybrid::RecebidaIndexada)
  end
  # Excluir a caixa oficial apaga a conexão, que desliga a sessão no motor.
  unless Inbox.reflect_on_association(:whatsapp_hybrid_connection)
    Inbox.has_one :whatsapp_hybrid_connection, class_name: 'WhatsappHybrid::Connection', dependent: :destroy
  end
end
