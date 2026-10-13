# Botão de link (chat#1473):
#   { "type": "link_button", "label": "Abrir", "url": "https://...", "header": "Proposta", "footer": "Válida hoje" }
# `header` e `footer` são opcionais. Limites da Meta para o `cta_url`: rótulo até 20 caracteres, corpo até 1024,
# cabeçalho de texto e rodapé até 60. Valem em qualquer canal, para o mesmo pedido ter o mesmo resultado onde
# quer que a conversa esteja.
class RichMessages::Types::LinkButton
  LABEL_MAX = 20
  BODY_MAX = 1024
  EDGE_MAX = 60
  URL_FORBIDDEN = [' ', '"', "'", '<', '>'].freeze

  BODY_BLANK = 'O botão de link precisa de um texto na mensagem.'.freeze
  BODY_TOO_LONG = "O texto da mensagem com botão de link passa de #{BODY_MAX} caracteres.".freeze
  LABEL_BLANK = 'O botão de link está sem o texto do botão.'.freeze
  LABEL_TOO_LONG = "O texto do botão de link passa de #{LABEL_MAX} caracteres.".freeze
  INVALID_URL = 'O endereço do botão de link precisa ser um endereço completo, começando com http:// ou https://.'.freeze
  HEADER_INVALID = "O cabeçalho do botão de link precisa ser um texto de até #{EDGE_MAX} caracteres.".freeze
  FOOTER_INVALID = "O rodapé do botão de link precisa ser um texto de até #{EDGE_MAX} caracteres.".freeze

  def initialize(payload)
    @label = payload['label']
    @url = payload['url']
    @header = payload['header']
    @footer = payload['footer']
  end

  def error_for(body)
    body_error(body) || label_error || url_error || edge_error(@header, HEADER_INVALID) || edge_error(@footer, FOOTER_INVALID)
  end

  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-cta-url-messages
  def whatsapp_cloud_payload(body)
    {
      type: 'interactive',
      interactive: {
        type: 'cta_url',
        header: (@header && { type: 'text', text: @header }),
        body: { text: body },
        footer: (@footer && { text: @footer }),
        action: { name: 'cta_url', parameters: { display_text: @label, url: @url } }
      }.compact
    }
  end

  # Só o rótulo e o endereço, com o endereço no fim da linha (os aplicativos o tornam clicável).
  # Cabeçalho e rodapé não entram: são moldura do cartão, e em texto corrido confundem com o corpo.
  def fallback_text(_body)
    "#{@label}: #{@url}"
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
    INVALID_URL unless @url.is_a?(String) && URL_FORBIDDEN.none? { |character| @url.include?(character) } && web_address?
  end

  def web_address?
    uri = URI.parse(@url)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def edge_error(text, error)
    error unless text.nil? || (text.is_a?(String) && text.strip.present? && text.length <= EDGE_MAX)
  end
end
