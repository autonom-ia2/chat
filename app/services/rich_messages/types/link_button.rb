# Botão de link (chat#1473): `{ "type": "link_button", "label": "Abrir", "url": "https://..." }`.
# Limites da Meta para o `cta_url`: rótulo até 20 caracteres, corpo até 1024. Valem em qualquer canal, para o
# mesmo pedido ter o mesmo resultado onde quer que a conversa esteja.
class RichMessages::Types::LinkButton
  LABEL_MAX = 20
  BODY_MAX = 1024
  URL_SCHEMES = ['http://', 'https://'].freeze

  BODY_BLANK = 'O botão de link precisa de um texto na mensagem.'.freeze
  BODY_TOO_LONG = "O texto da mensagem com botão de link passa de #{BODY_MAX} caracteres.".freeze
  LABEL_BLANK = 'O botão de link está sem o texto do botão.'.freeze
  LABEL_TOO_LONG = "O texto do botão de link passa de #{LABEL_MAX} caracteres.".freeze
  INVALID_URL = 'O endereço do botão de link precisa começar com http:// ou https://.'.freeze

  def initialize(payload)
    @label = payload['label']
    @url = payload['url']
  end

  def error_for(body)
    body_error(body) || label_error || url_error
  end

  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-cta-url-messages
  def whatsapp_cloud_payload(body)
    {
      type: 'interactive',
      interactive: { type: 'cta_url', body: { text: body }, action: { name: 'cta_url', parameters: { display_text: @label, url: @url } } }
    }
  end

  def fallback_text(body)
    "#{body}\n\n#{@url}"
  end

  private

  def body_error(body)
    return BODY_BLANK if body.blank?

    BODY_TOO_LONG if body.length > BODY_MAX
  end

  def label_error
    return LABEL_BLANK unless @label.is_a?(String) && @label.strip.present?

    LABEL_TOO_LONG if @label.length > LABEL_MAX
  end

  def url_error
    INVALID_URL unless @url.is_a?(String) && @url.start_with?(*URL_SCHEMES)
  end
end
