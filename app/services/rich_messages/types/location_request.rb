# Pedido de localização (chat#1473, P5):
#   { "type": "location_request" }
# O cliente recebe o corpo com o botão "Enviar localização" do próprio WhatsApp. Corpo obrigatório, até 1024
# caracteres (limite da Meta). Sem cabeçalho nem rodapé: a página da Meta não os documenta para este formato.
# A resposta do cliente chega como localização (ver RichMessages::ReceivedLocation).
class RichMessages::Types::LocationRequest
  BODY_MAX = 1024

  BODY_BLANK = 'O pedido de localização precisa de um texto na mensagem.'.freeze
  BODY_TOO_LONG = "O texto do pedido de localização passa de #{BODY_MAX} caracteres.".freeze

  def initialize(_payload); end

  def error_for(body)
    return BODY_BLANK if body.blank?

    BODY_TOO_LONG if body.length > BODY_MAX
  end

  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/location-request-messages
  def whatsapp_cloud_payload(body)
    {
      type: 'interactive',
      interactive: { type: 'location_request_message', body: { text: body }, action: { name: 'send_location' } }
    }
  end

  # Em texto, o próprio corpo já pede o endereço: nada a acrescentar.
  def fallback_text(_body)
    ''
  end
end
