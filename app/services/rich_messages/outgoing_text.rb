# Prepend em Message (chat#1473): o texto de saída de uma mensagem com `rich_message` é o texto de reserva do
# tipo. É o que recebem os canais que montam o envio por `outgoing_content` e não têm o formato: WhatsApp de
# outro provedor, WhatsApp Híbrido, Telegram, Instagram, Messenger, SMS, Line, e-mail.
# O WhatsApp oficial não passa por aqui: usa RichMessages.body_text. Senão, no botão de link, o endereço
# sairia duas vezes, no corpo e no botão.
module RichMessages::OutgoingText
  def outgoing_content
    rich = RichMessages.build(self)
    rich ? rich.fallback_text(super) : super
  end
end
