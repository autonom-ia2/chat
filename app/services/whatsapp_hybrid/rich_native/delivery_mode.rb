# Prepend na classe singleton de RichMessages (chat#1709). Dois pontos, sem editar rich_messages.rb:
# - delivery_mode: numa caixa híbrida com a flag `whatsapp_rich_native`, responde `:native` (em vez de `:text`) só
#   quando o envio mandaria nativo (WhatsappHybrid::RichNative.native_for?: a mesma regra do roteador e do tradutor).
#   `message:` (opcional, acrescentado aqui): a mensagem que vai ser enviada, para decidir também pelo conteúdo (a
#   lista depende dele). Sem `conversation`, a resposta continua a original.
#   Quem consulta hoje (git grep, 16/10/2026): só Crm::BookingV2::Notices::Button, com `link_button`, que não muda.
# - mark_sent_as_text!: mensagem que já saiu nativa pelo WhatsApp API (RichNative::Transport) não ganha a marca de
#   texto que o WebTransport grava depois de todo envio.
module WhatsappHybrid::RichNative::DeliveryMode
  def delivery_mode(inbox:, type:, conversation: nil, message: nil)
    mode = super(inbox: inbox, type: type, conversation: conversation)
    return mode unless mode == :text && conversation.present?

    WhatsappHybrid::RichNative.native_for?(inbox, type, conversation, message: message) ? :native : mode
  end

  def mark_sent_as_text!(message)
    return if WhatsappHybrid::RichNative.sent_native?(message)

    super
  end
end
