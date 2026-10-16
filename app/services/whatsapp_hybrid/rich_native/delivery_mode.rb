# Prepend na classe singleton de RichMessages (chat#1709). Dois pontos, sem editar rich_messages.rb:
# - delivery_mode: a caixa híbrida com a flag `whatsapp_rich_native` e o WhatsApp API pronto para a conversa responde
#   `:native` (em vez de `:text`) para options, location e contact. Sem `conversation` a janela é desconhecida e a
#   resposta continua a original. Decide por caixa, tipo e conversa, como o original: uma lista que não caiba nos
#   limites do WhatsApp ainda sai como texto no envio.
# - mark_sent_as_text!: mensagem que já saiu nativa pelo WhatsApp API (RichNative::Transport) não ganha a marca de
#   texto que o WebTransport grava depois de todo envio.
module WhatsappHybrid::RichNative::DeliveryMode
  def delivery_mode(inbox:, type:, conversation: nil)
    mode = super
    return mode unless mode == :text && conversation.present?

    WhatsappHybrid::RichNative.native_for?(inbox, type, conversation) ? :native : mode
  end

  def mark_sent_as_text!(message)
    return if WhatsappHybrid::RichNative.sent_native?(message)

    super
  end
end
