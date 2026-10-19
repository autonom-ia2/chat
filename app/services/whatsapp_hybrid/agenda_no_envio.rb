# #1865 — prepend em WhatsappHybrid::WebTransport: antes de o Híbrido enviar pelo WhatsApp API, o contato fica salvo na
# agenda do aparelho (Waha::AgendaDoContato). Logo antes do "digitando" e do envio, depois de o contato ter WhatsApp
# confirmado. Cobre tudo o que sai pelo Web: atendente, robô, follow-up, mensagem rica e o plano B do 131047.
# A agenda é pelo número do contato, não pelo `chat_id` do envio (que pode ser `@lid`): ver Waha::AgendaDoContato.
# A lida da resposta vai pela Cloud, no SendReplyJob (ConversaCanal::LeituraAoResponder).
module WhatsappHybrid::AgendaNoEnvio
  private

  def send_now(chat_id)
    if Waha::AgendaDoContato.enabled?(@connection.account)
      Waha::AgendaDoContato.new(client: @client, session: session, contact: @message.conversation.contact).garantir
    end
    super
  end
end
