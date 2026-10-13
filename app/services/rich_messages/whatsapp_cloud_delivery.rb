# Prepend em Whatsapp::Providers::WhatsappCloudService (chat#1473): mensagem com `rich_message` sai no formato
# da Meta, corpo e formato na mesma mensagem. Sem `rich_message`, o envio original, intocado.
# Com anexo segue o envio de anexo: a legenda é o texto de reserva do tipo.
# Graph recente, como o pedido de telefone: o v13.0 do envio de texto não é alterado.
module RichMessages::WhatsappCloudDelivery
  def send_message(phone_number, message)
    rich = RichMessages.build(message)
    return super if rich.nil? || message.attachments.present?

    response = HTTParty.post(
      "#{phone_id_path(GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0'))}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        **recipient_params(phone_number),
        **rich.whatsapp_cloud_payload(RichMessages.body_text(message))
      }.to_json
    )

    process_response(response, message)
  end
end
