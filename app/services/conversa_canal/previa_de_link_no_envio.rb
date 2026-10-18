# Prepend em Whatsapp::Providers::WhatsappCloudService (#1702). Texto comum do atendente com endereço sai com
# `preview_url: true`, e o celular do cliente mostra a prévia como no app. Regra da Meta: só o PRIMEIRO endereço do
# texto ganha a prévia, e ele precisa começar com http:// ou https://; sem `preview_url`, ou se o WhatsApp não
# conseguir montar a prévia, o cliente vê o link clicável.
# https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/text-messages
# Sem endereço válido ou com a chave `conversa_cara_do_canal` desligada, o envio original e mais nada. O pedido é o
# mesmo do Chatwoot (mesma versão da Graph), com `preview_url` a mais. Mensagem rica não passa por aqui
# (RichMessages::WhatsappCloudDelivery cuida dela, e a prévia de link rica já leva `preview_url`).
module ConversaCanal::PreviaDeLinkNoEnvio
  private

  def send_text_message(phone_number, message)
    return super unless previa_no_envio?(message)

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        **recipient_params(phone_number),
        text: { body: message.outgoing_content, preview_url: true },
        type: 'text'
      }.to_json
    )

    process_response(response, message)
  end

  # Só mensagem do painel: campanha e jornada também mandam texto por aqui com objetos que não são Message.
  def previa_no_envio?(message)
    message.is_a?(Message) &&
      message.account.feature_enabled?(ConversaCanal::PreviaDeLink::FLAG) &&
      ConversaCanal::PreviaDeLink.endereco(message.outgoing_content).present?
  end
end
