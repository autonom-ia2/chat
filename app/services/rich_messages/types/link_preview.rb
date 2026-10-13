# Prévia de link (chat#1473, P6): o corpo sai como texto e o WhatsApp tenta mostrar a miniatura da página do
# PRIMEIRO endereço do texto.
#   { "type": "link_preview" }
# Sem outros campos: o endereço é o que está no corpo. Regras da Meta para o `text` com `preview_url`: corpo até
# 4096 caracteres; só o primeiro endereço ganha prévia, e endereço só conta se começar com http:// ou https://.
# A miniatura depende da página (e do aparelho do cliente): sem ela, o cliente vê o link clicável.
# Valem em qualquer canal, para o mesmo pedido ter o mesmo resultado onde quer que a conversa esteja.
class RichMessages::Types::LinkPreview
  BODY_MAX = 4096
  WEB_PREFIXES = ['http://', 'https://'].freeze

  NO_WEB_ADDRESS = 'A mensagem com prévia de link precisa ter no texto um endereço completo, começando com http:// ou https://.'.freeze
  BODY_TOO_LONG = "O texto da mensagem com prévia de link passa de #{BODY_MAX} caracteres.".freeze

  def initialize(_payload); end

  def error_for(body)
    return BODY_TOO_LONG if body.length > BODY_MAX

    NO_WEB_ADDRESS unless body.split.any? { |word| web_address?(word) }
  end

  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/text-messages
  def whatsapp_cloud_payload(body)
    { type: 'text', text: { body: body, preview_url: true } }
  end

  # Em branco: a versão em texto é só o corpo, que já traz o endereço.
  def fallback_text(_body)
    ''
  end

  private

  # A palavra tem um endereço http(s) com host a partir de onde o esquema começa: pontuação em volta, como em
  # "(https://exemplo.com.br).", não impede. Addressable porque aceita domínio com acento, como no botão de link.
  def web_address?(word)
    start = WEB_PREFIXES.filter_map { |prefix| word.index(prefix) }.min
    start.present? && Addressable::URI.parse(word[start..]).host.present?
  rescue Addressable::URI::InvalidURIError
    false
  end
end
