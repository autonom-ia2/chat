# Prepend em Message (chat#1473): o texto de saída de uma mensagem com `rich_message` é o corpo mais a versão
# em texto do tipo. É o que recebem os canais que montam o envio por `outgoing_content` e não têm o formato:
# WhatsApp de outro provedor (360dialog, Twilio), WhatsApp Híbrido, Telegram, Instagram, Messenger, SMS, Line.
# Onde o texto de saída é HTML (Telegram), o complemento vai escapado.
# O WhatsApp oficial não passa por aqui: usa RichMessages.body_text. Senão, no botão de link, o endereço
# sairia duas vezes, no corpo e no botão. E-mail e chat do site não leem este texto: lá a mensagem é recusada
# (RichMessages::UNSUPPORTED_CHANNELS).
# Sem `rich_message`, o método original e mais nada.
module RichMessages::OutgoingText
  def outgoing_content
    return super unless RichMessages.rich?(self)

    RichMessages.text_with_fallback(self, super, html: RichMessages.html_channel?(inbox))
  end
end
