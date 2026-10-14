# Prévia de link (chat#1473, P6): o corpo sai como texto e o WhatsApp tenta mostrar a miniatura da página do
# PRIMEIRO endereço do texto.
#   { "type": "link_preview" }
# Sem outros campos: o endereço é o que está no corpo. Regras da Meta para o `text` com `preview_url`: corpo até
# 4096 caracteres; só o primeiro endereço ganha prévia, e endereço só conta se começar com http:// ou https://.
# Por isso quem decide é o primeiro endereço: se ele não for válido, a mensagem é recusada, mesmo que outro
# endereço depois dele seja. A miniatura depende da página (e do aparelho do cliente): sem ela, o cliente vê o
# link clicável.
# As regras valem em todo canal que aceita o formato, para o mesmo pedido ter o mesmo resultado; e-mail e chat do
# site recusam qualquer `rich_message` (RichMessages::UNSUPPORTED_CHANNELS).
class RichMessages::Types::LinkPreview
  BODY_MAX = 4096
  WEB_PREFIXES = ['http://', 'https://'].freeze
  WEB_SCHEMES = %w[http https].freeze
  # Espaços que o `split` não separa sozinho: sem quebra (U+00A0), estreito sem quebra (U+202F) e ideográfico
  # (U+3000). Viram espaço comum antes de quebrar o texto em palavras.
  UNICODE_SPACES = "\u00A0\u202F\u3000".freeze
  # Caracteres que nunca fazem parte de um endereço sem escape (RFC 3986): onde aparecem, o endereço acabou. No
  # texto em HTML do Telegram é o fim do `href="..."` ou o começo de uma tag (`<strong>`, `<em>`).
  ADDRESS_ENDS = ['"', '<', '>'].freeze
  # Pontuação que fecha a frase, não o endereço: "veja https://exemplo.com.br." ou "(https://exemplo.com.br)…", e os
  # marcadores de formatação do WhatsApp em volta do endereço (`*negrito*`, `_itálico_`, `~riscado~`).
  TRAILING_PUNCTUATION = ['.', ',', ';', ':', '!', '?', ')', ']', '}', "'", '…', '*', '_', '~'].freeze

  NO_WEB_ADDRESS = 'A mensagem com prévia de link precisa ter no texto um endereço completo, começando com http:// ou https://.'.freeze
  INVALID_FIRST_ADDRESS = 'O primeiro endereço do texto, o que ganha a prévia, não é um endereço completo ' \
                          '(por exemplo https://exemplo.com.br).'.freeze
  BODY_TOO_LONG = "O texto da mensagem com prévia de link passa de #{BODY_MAX} caracteres.".freeze

  def initialize(_payload); end

  def error_for(body)
    return BODY_TOO_LONG if body.length > BODY_MAX

    candidate = first_candidate(body)
    return NO_WEB_ADDRESS if candidate.nil?

    INVALID_FIRST_ADDRESS unless web_address?(candidate)
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

  # O primeiro trecho do texto que começa com http:// ou https:// (em qualquer caixa), do esquema até o fim da
  # palavra (ou até um caractere de ADDRESS_ENDS), sem a pontuação que fecha a frase. Nil quando o texto não tem
  # nenhum.
  def first_candidate(body)
    body.tr(UNICODE_SPACES, ' ').split.lazy.filter_map { |word| candidate_in(word) }.first
  end

  def candidate_in(word)
    lowered = word.downcase(:ascii)
    start = WEB_PREFIXES.filter_map { |prefix| lowered.index(prefix) }.min
    without_trailing_punctuation(up_to_address_end(word[start..])) if start
  end

  def up_to_address_end(text)
    finish = ADDRESS_ENDS.filter_map { |character| text.index(character) }.min
    finish ? text[0, finish] : text
  end

  def without_trailing_punctuation(text)
    trimmed = text
    trimmed = trimmed.chop while TRAILING_PUNCTUATION.include?(trimmed[-1])
    trimmed
  end

  # Esquema e host decididos pelo Addressable depois de normalizar, como no botão de link: esquema em minúsculas,
  # domínio com acento em punycode.
  def web_address?(candidate)
    uri = Addressable::URI.parse(candidate).normalize
    WEB_SCHEMES.include?(uri.scheme) && named_host?(uri.host)
  rescue Addressable::URI::InvalidURIError
    false
  end

  # Host com pelo menos duas partes não vazias separadas por ponto (`exemplo.com.br`, `192.168.0.1`). Recusa `.`,
  # `exemplo..com` e nome de uma parte só (`localhost`), que o aparelho do cliente não alcança.
  def named_host?(host)
    labels = host.to_s.split('.', -1)
    labels.size >= 2 && labels.none?(&:empty?)
  end
end
