# Reagir e editar pelo painel na caixa WAHA comum (chat#1709, fase 3). O chat2you grava a mudança na mensagem e manda
# ao webhook da caixa um evento próprio, que o conector customizado (c2y-rich-2) leva ao motor:
#   { event: 'c2y_message_reaction', ...message.webhook_data, c2y_reaction: { emoji } }   ('' = remover)
#   { event: 'c2y_message_edit',     ...message.webhook_data, c2y_edit: { waha_text } }
# Um motor sem o patch ignora o evento (o conector original devolve null para evento desconhecido). A gravação não
# manda `message_updated` ao conector (Waha::RichNative::SilentUpdate): o evento próprio é o único pedido.
# Só com a flag `whatsapp_rich_native`, na caixa WAHA comum cujo motor declara a ação (Waha::EngineCapabilities.actions).
# Cada método devolve nil quando gravou e pediu o envio, :unchanged na edição com o mesmo texto (nada gravado nem
# enviado), ou o motivo da recusa (símbolo; o controller responde 403/422).
# O envio ao conector é assíncrono e com nova tentativa; se não chegar, fica uma nota privada na conversa.
# - A reação é da EMPRESA (Waha::RichNative::Reactions): a de um atendente troca a de outro, como no WhatsApp.
# - Editar: só quem enviou a mensagem, ou um administrador da conta (a do robô, da IA ou de outro atendente só pelo
#   administrador); o histórico guarda quem editou.
module Waha::RichNative::MessageActions
  # Margem sob os 15 minutos que o WhatsApp dá para editar (o painel usa o mesmo, EDIT_WINDOW_SECONDS).
  EDIT_WINDOW = 14.minutes
  REACTION_EVENT = 'c2y_message_reaction'.freeze
  EDIT_EVENT = 'c2y_message_edit'.freeze

  module_function

  def allowed?(conversation, action)
    Waha::RichNative::WahaInbox.message_actions_for(conversation).include?(action)
  end

  def react!(message, user:, emoji:)
    return :forbidden unless allowed?(message.conversation, 'react')
    return :invalid unless reactable?(message) && Waha::RichNative::Reactions.valid_emoji?(emoji)

    Waha::RichNative::Reactions.apply!(message, emoji: emoji, author: Waha::RichNative::Reactions.business_author(user.id))
    deliver(message, REACTION_EVENT)
    nil
  end

  def edit!(message, user:, content:, administrator: false)
    return :forbidden unless allowed?(message.conversation, 'edit')
    return :invalid unless editable?(message) && Waha::RichNative::Edits.valid_text?(content)
    return :not_author unless administrator || author?(message, user)
    return :unchanged unless Waha::RichNative::Edits.apply!(message, content: content, author: Waha::RichNative::Edits.user_author(user.id))

    deliver(message, EDIT_EVENT)
    nil
  end

  # A regra única do Whatsapp::MensagemReagivel (a mesma da reação pela pele): nem nota, atividade, modelo, apagada
  # (pelo painel ou pelo cliente), falhada, nem o aviso de visualização única.
  def reactable?(message)
    Whatsapp::MensagemReagivel.reagivel?(message)
  end

  # Só texto nosso, sem anexo nem formato, que não falhou, dentro da janela do WhatsApp.
  def editable?(message)
    plain_text?(message) && !message.failed? && !message.content_attributes.to_h['deleted'] &&
      message.content_attributes.to_h['external_error'].blank? && message.created_at >= EDIT_WINDOW.ago
  end

  def plain_text?(message)
    message.outgoing? && !message.private? && message.content_type == 'text' && message.attachments.empty? && !RichMessages.rich?(message)
  end

  def author?(message, user)
    message.sender_type == 'User' && message.sender_id == user.id
  end

  # O evento vai ao webhook da caixa com as mesmas travas da entrega de sempre (endereço e trava de transmissão), por um
  # job que tenta de novo e, se não chegar, deixa a nota na conversa (Waha::RichNative::MessageActionDeliveryJob).
  # O job monta o evento na hora da entrega, do estado atual da mensagem. Se o pedido nem pode sair (caixa sem webhook,
  # trava de transmissão), a mesma nota, na hora: gravado no painel, mas não chegou ao WhatsApp.
  def deliver(message, event)
    channel = message.inbox.channel
    if channel.webhook_url.blank? || ::Autonomia::Channels::BroadcastGuard.blocked_conversation?(message.conversation)
      Rails.logger.error("[waha] message action not sent message=#{message.id} #{event} blocked_or_no_webhook")
      return Waha::RichNative::MessageActionDeliveryJob.note_not_delivered!(message, event)
    end

    Waha::RichNative::MessageActionDeliveryJob.request!(message, event)
  end
end
