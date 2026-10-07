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
  # Excluir a caixa oficial apaga a conexão, que desliga a sessão no motor.
  unless Inbox.reflect_on_association(:whatsapp_hybrid_connection)
    Inbox.has_one :whatsapp_hybrid_connection, class_name: 'WhatsappHybrid::Connection', dependent: :destroy
  end
end
