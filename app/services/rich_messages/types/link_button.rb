# Botão de link (chat#1473):
#   { "type": "link_button", "label": "Abrir", "url": "https://...", "header": "Proposta", "footer": "Válida hoje" }
# `header` e `footer` são opcionais. Limites da Meta para o `cta_url`: rótulo até 20 caracteres, corpo até 1024,
# cabeçalho de texto e rodapé até 60; rótulo, cabeçalho e rodapé em uma linha só. Valem em qualquer canal, para o
# mesmo pedido ter o mesmo resultado onde quer que a conversa esteja.
class RichMessages::Types::LinkButton
  LABEL_MAX = 20
  BODY_MAX = 1024
  EDGE_MAX = 60
  URL_FORBIDDEN = [' ', '"', "'", '<', '>'].freeze
  WEB_SCHEMES = %w[http https].freeze
  # Limite que a Meta documenta para endereço em botão de modelo; para o `cta_url` livre ela não dá número.
  URL_MAX = 2000
  LINE_BREAKS = ["\n", "\r"].freeze

  BODY_BLANK = 'O botão de link precisa de um texto na mensagem.'.freeze
  BODY_TOO_LONG = "O texto da mensagem com botão de link passa de #{BODY_MAX} caracteres.".freeze
  LABEL_BLANK = 'O botão de link está sem o texto do botão.'.freeze
  LABEL_TOO_LONG = "O texto do botão de link passa de #{LABEL_MAX} caracteres.".freeze
  LABEL_MULTILINE = 'O texto do botão de link precisa ficar em uma linha só.'.freeze
  URL_TOO_LONG = "O endereço do botão de link passa de #{URL_MAX} caracteres.".freeze
  INVALID_URL = 'O endereço do botão de link precisa ser um endereço completo, começando com http:// ou https://.'.freeze
  HEADER_INVALID = "O cabeçalho do botão de link precisa ser um texto de até #{EDGE_MAX} caracteres, em uma linha só.".freeze
  FOOTER_INVALID = "O rodapé do botão de link precisa ser um texto de até #{EDGE_MAX} caracteres, em uma linha só.".freeze

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
        action: { name: 'cta_url', parameters: { display_text: @label, url: web_address } }
      }.compact
    }
  end

  # Só o rótulo e o endereço, com o endereço no fim da linha (os aplicativos o tornam clicável), como veio do
  # robô (legível, com acento). Cabeçalho e rodapé não entram: são moldura do cartão, e em texto corrido confundem
  # com o corpo.
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
    return LABEL_MULTILINE unless one_line?(@label)

    LABEL_TOO_LONG if @label.length > LABEL_MAX
  end

  # O tamanho é conferido antes de interpretar o endereço.
  def url_error
    return INVALID_URL unless @url.is_a?(String)
    return URL_TOO_LONG if @url.length > URL_MAX

    INVALID_URL unless URL_FORBIDDEN.none? { |character| @url.include?(character) } && web_address
  end

  # O endereço normalizado em ASCII, como vai para a Meta: acento no caminho e na consulta vira %XX e domínio com
  # acento vira punycode (`açaí.com.br` → `xn--aa-4iaz.com.br`). Nil quando não é endereço http(s) com host.
  # Addressable porque a biblioteca padrão não converte domínio com acento; o próprio Chatwoot já o usa
  # (Whatsapp::PopulateTemplateParametersService).
  def web_address
    uri = Addressable::URI.parse(@url).normalize
    uri.to_s if WEB_SCHEMES.include?(uri.scheme) && uri.host.present?
  rescue Addressable::URI::InvalidURIError
    nil
  end

  def edge_error(text, error)
    error unless text.nil? || (text.is_a?(String) && text.strip.present? && text.length <= EDGE_MAX && one_line?(text))
  end

  def one_line?(text)
    LINE_BREAKS.none? { |line_break| text.include?(line_break) }
  end
end
