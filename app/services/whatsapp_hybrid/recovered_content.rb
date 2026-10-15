# O texto de uma mensagem que o motor (WAHA com GOWS) devolve em GET /chats/{chat}/messages/{id} (chat#1489).
#
# O conteúdo vem em `_data.Message`: a mensagem do protobuf do WhatsApp (waE2E do whatsmeow) em JSON. Leitura
# estrutural, campo a campo, sem regex. Os nomes dos campos são os do .proto (`templateMessage`,
# `hydratedContentText`…). O GOWS serializa com o encoding/json do Go: um `oneof` do proto vira um invólucro com nome
# de campo Go, em maiúscula (`"Format": {"HydratedFourRowTemplate": {...}}`, `"HydratedButton": {"QuickReplyButton":
# ...}`). `field` aceita as duas formas (direta, como no protojson, e dentro do invólucro) e ignora maiúsculas.
# `contextInfo` (mensagem citada) nunca é lido: o texto citado não é desta mensagem.
#
# Resultado: `kind` :text (com `text`), :media (com a legenda em `text`, se houver) ou :empty (nada legível).
class WhatsappHybrid::RecoveredContent
  # header_media: :image ou :media quando o cabeçalho do modelo traz um arquivo (não é baixado; fica para a PR 3).
  Result = Struct.new(:kind, :text, :header_media)

  # Invólucros que só embrulham outra mensagem em `.message`.
  WRAPPERS = %w[ephemeralMessage viewOnceMessage viewOnceMessageV2 viewOnceMessageV2Extension documentWithCaptionMessage
                deviceSentMessage].freeze
  MEDIA = %w[imageMessage videoMessage audioMessage documentMessage stickerMessage ptvMessage].freeze
  HEADER_MEDIA = %w[videoMessage documentMessage locationMessage].freeze
  TEXT_READERS = %i[plain_text template_text interactive_text buttons_text list_text].freeze

  def self.from_payload(payload)
    new(payload).result
  end

  def initialize(payload)
    @payload = payload.is_a?(Hash) ? payload : {}
  end

  def result
    message = proto_message
    return from_engine_fields if message.nil?

    text = TEXT_READERS.lazy.filter_map { |reader| send(reader, message).presence }.first
    return Result.new(:text, text, header_media(message)) if text

    media = MEDIA.lazy.filter_map { |name| field(message, name) }.first
    return Result.new(:media, string(field(media, 'caption'))) if media

    Result.new(:empty, nil)
  end

  private

  def proto_message
    message = field(field(@payload, '_data'), 'message')
    return unless message.is_a?(Hash)

    unwrap(message)
  end

  def unwrap(message)
    WRAPPERS.each do |name|
      inner = field(field(message, name), 'message')
      return unwrap(inner) if inner.is_a?(Hash)
    end
    message
  end

  # Sem `_data`: o que o motor normaliza no topo (`body`, `hasMedia`).
  def from_engine_fields
    body = string(@payload['body'])
    return Result.new(:media, body) if @payload['hasMedia'] == true
    return Result.new(:text, body) if body

    Result.new(:empty, nil)
  end

  def plain_text(message)
    string(field(message, 'conversation')) || string(field(field(message, 'extendedTextMessage'), 'text'))
  end

  # Modelo com botões de outra empresa (o caso do spike, 6/6).
  def template_text(message)
    template = field(message, 'templateMessage')
    return if template.nil?

    hydrated = field(template, 'hydratedTemplate') || field(template, 'hydratedFourRowTemplate')
    return hydrated_text(hydrated) if hydrated

    interactive_body(field(template, 'interactiveMessageTemplate'))
  end

  # Cabeçalho do modelo: `Title` (hydrated) ou `header.Media` (interativo). Os dois são `oneof`, embrulhados.
  def header_media(message)
    header = template_header(field(message, 'templateMessage')) || field(field(message, 'interactiveMessage'), 'header')
    return if header.nil?
    return :image if field(header, 'imageMessage')

    :media if HEADER_MEDIA.any? { |name| field(header, name) }
  end

  def template_header(template)
    hydrated = field(template, 'hydratedTemplate') || field(template, 'hydratedFourRowTemplate')
    return hydrated if hydrated

    field(field(template, 'interactiveMessageTemplate'), 'header')
  end

  def hydrated_text(template)
    compose([field(template, 'hydratedTitleText'), field(template, 'hydratedContentText'), field(template, 'hydratedFooterText')],
            Array(field(template, 'hydratedButtons')).map { |button| hydrated_button(button) })
  end

  def hydrated_button(button)
    quick = field(button, 'quickReplyButton')
    return label(quick) if quick

    url = field(button, 'urlButton')
    return labelled(label(url), field(url, 'url')) if url

    call = field(button, 'callButton')
    labelled(label(call), field(call, 'phoneNumber')) if call
  end

  def interactive_text(message)
    interactive_body(field(message, 'interactiveMessage'))
  end

  def interactive_body(interactive)
    return if interactive.nil?

    buttons = Array(field(field(interactive, 'nativeFlowMessage'), 'buttons')).map { |button| native_flow_button(button) }
    compose([field(field(interactive, 'header'), 'title'), field(field(interactive, 'body'), 'text'),
             field(field(interactive, 'footer'), 'text')], buttons)
  end

  # `buttonParamsJSON` é um JSON dentro do JSON: { "display_text": "...", "url": "...", "phone_number": "..." }.
  def native_flow_button(button)
    params = JSON.parse(field(button, 'buttonParamsJSON').to_s)
    return unless params.is_a?(Hash)

    labelled(string(params['display_text']), params['url'] || params['phone_number'])
  rescue JSON::ParserError
    nil
  end

  def buttons_text(message)
    buttons = field(message, 'buttonsMessage')
    return if buttons.nil?

    compose([field(buttons, 'text'), field(buttons, 'contentText'), field(buttons, 'footerText')],
            Array(field(buttons, 'buttons')).map { |button| string(field(field(button, 'buttonText'), 'displayText')) })
  end

  def list_text(message)
    list = field(message, 'listMessage')
    return if list.nil?

    rows = Array(field(list, 'sections')).flat_map { |section| Array(field(section, 'rows')) }
    compose([field(list, 'title'), field(list, 'description'), field(list, 'footerText')],
            rows.map { |row| string(field(row, 'title')) })
  end

  # Título, corpo e rodapé em parágrafos; os botões numerados, como a versão em texto das opções
  # (RichMessages::Types::Options#fallback_text).
  def compose(parts, buttons)
    lines = buttons.compact_blank.each_with_index.map { |text, index| "#{index + 1}. #{text}" }
    [*parts.filter_map { |part| string(part) }, lines.join("\n").presence].compact.join("\n\n").presence
  end

  def label(button)
    string(field(button, 'displayText'))
  end

  def labelled(text, detail)
    [text, string(detail)].compact.join(': ').presence
  end

  def string(value)
    value.is_a?(String) ? value.strip.presence : nil
  end

  # O campo `name` do nó, direto ou dentro do invólucro de um `oneof`.
  def field(node, name)
    return unless node.is_a?(Hash)

    found = named(node, name) || node.lazy.filter_map { |key, value| named(value, name) if oneof_wrapper?(key) }.first
    found&.last
  end

  def named(node, name)
    node.find { |key, _value| key.to_s.casecmp?(name) } if node.is_a?(Hash)
  end

  # Campo Go de um `oneof`: começa em maiúscula. Os campos do proto começam em minúscula.
  def oneof_wrapper?(key)
    first = key.to_s[0].to_s
    first != first.downcase
  end
end
