# Traduz o formato rico do painel (`content_attributes.rich_message`, chat#1473) para o envio nativo do WAHA (chat#1709).
# Só conhece o motor: não sabe de caixa, conta, flag nem WhatsApp Híbrido, para servir também à caixa WAHA comum.
#
#   Waha::RichPayload.build(rich_message, body: 'Qual horário?', locale: 'pt_BR', reference: 123)  # => instância, ou nil
#   payload.deliver(client, session: 'hybrid-55...', chat_id: '55...@c.us', id: '3EB0...')
#
# nil quer dizer "não sai nativo": o tipo não tem envio nativo no motor (link_button, location_request, flow,
# link_preview), a entrada está fora do contrato, ou não cabe nos limites da lista do WhatsApp. Quem chama manda o
# texto, como antes.
#
# - options sai sempre como LISTA (`sendList`), mesmo com até 3 opções sem descrição: o motor (GOWS) não tem botões
#   (`sendButtons` responde 501). O `id` de cada opção vira o `rowId`, que volta na resposta do cliente.
# - location sai por `sendLocation`; contact por `sendContactVcard`.
#
# Teste em aparelho real (16/10/2026, motor 2026.9.2 GOWS PLUS): os três chegam nativos (comentário na #1709).
class Waha::RichPayload
  # Limites da lista do WhatsApp. Passou de um deles, sai texto.
  ROWS_MAX = 10
  ROW_TITLE_MAX = 24
  ROW_DESCRIPTION_MAX = 72
  ROW_ID_MAX = 200
  BUTTON_MAX = 20
  SECTION_TITLE_MAX = 24
  # O título da lista (o cabeçalho, ou o corpo quando não há cabeçalho): o limite do cabeçalho de texto da Meta.
  TITLE_MAX = 60
  # As mesmas quebras de linha que o tipo `options` recusa.
  LINE_BREAKS = RichMessages::Types::Options::LINE_BREAKS

  KINDS = %w[options location contact].freeze

  attr_reader :kind

  # reference: o id da mensagem no Chatwoot, que vai em cada `rowId` da lista (Waha::RichNative.row_id) para a resposta
  # do cliente voltar ligada a esta mensagem. Sem ela, o `rowId` é só o id da opção.
  def self.build(rich_message, body:, locale: I18n.default_locale, reference: nil)
    return unless rich_message.is_a?(Hash)

    rich = rich_message.with_indifferent_access
    return unless KINDS.include?(rich[:type])

    payload = new(rich, body: body.to_s, locale: locale, reference: reference)
    payload if payload.valid?
  end

  def initialize(rich, body:, locale:, reference: nil)
    @rich = rich
    @reference = reference
    @body = body
    @locale = locale
    @kind = rich[:type]
  end

  def valid?
    case @kind
    when 'options' then list_message.present?
    when 'location' then coordinates?
    when 'contact' then contact.present?
    else false
    end
  end

  # `sendList` não aceita id gerado antes (não está no contrato do motor); `sendLocation` e `sendContactVcard` aceitam.
  def pre_generated_id?
    @kind != 'options'
  end

  def deliver(client, session:, chat_id:, id:)
    case @kind
    when 'options' then client.send_list(session: session, chat_id: chat_id, message: list_message)
    when 'location' then client.send_location(session: session, chat_id: chat_id, id: id, location: location)
    when 'contact' then client.send_contact_vcard(session: session, chat_id: chat_id, id: id, contacts: [contact])
    end
  end

  # O id físico que o motor deu à mensagem, lido da resposta do envio: `id` como texto (`true_<chat>_<id>`, o mesmo
  # formato que o ack traz), `id` como objeto (`_serialized` ou `id`) ou `key.id`. nil quando a resposta não traz.
  def self.physical_id(response)
    return unless response.is_a?(Hash)

    value = response['id']
    value = value['_serialized'].presence || value['id'] if value.is_a?(Hash)
    value = response.dig('key', 'id') if value.blank? && response['key'].is_a?(Hash)
    value.to_s.split('_').last.presence
  end

  private

  # ---- options → lista ----
  def list_message
    return @list_message if defined?(@list_message)

    @list_message = build_list_message
  end

  def build_list_message
    sections = list_sections
    header = @rich[:header].presence
    title = header || @body
    # Sem cabeçalho, o corpo vira o título: precisa caber nele (até 60, uma linha só), senão sai texto.
    return if sections.nil? || @body.blank? || !line?(title, TITLE_MAX) || !line?(button, BUTTON_MAX)

    {
      title: title, description: (@body if header), footer: @rich[:footer].presence,
      button: button, sections: sections
    }.compact
  end

  def list_sections
    groups = option_groups
    return unless groups.to_a.sum { |(_title, options)| options.size }.between?(1, ROWS_MAX)

    sections = groups.map { |title, options| section(title, options) }
    sections unless sections.any?(&:nil?)
  end

  # [título, opções]; com `options` soltas, uma seção sem título.
  def option_groups
    sections = @rich[:sections]
    options = @rich[:options]
    return [[nil, options]] if options.is_a?(Array) && sections.nil?

    sections.map { |item| [item[:title], item[:options]] } if options.nil? && sections_shape?(sections)
  end

  def sections_shape?(sections)
    sections.is_a?(Array) && sections.all? { |item| item.is_a?(Hash) && item[:options].is_a?(Array) }
  end

  def section(title, options)
    title = title.presence || button
    return unless line?(title, SECTION_TITLE_MAX)

    rows = options.map { |option| row(option) }
    { title: title, rows: rows } unless rows.any?(&:nil?)
  end

  # Id de opção com o separador da referência ("|") não sai nativo: na volta não daria para separar a opção da
  # referência sem ambiguidade (Waha::RichNative.split_row_id). Sai texto, como antes.
  def row(option)
    return unless option.is_a?(Hash) && line?(option[:title], ROW_TITLE_MAX) && line?(option[:id], ROW_ID_MAX)
    return if option[:id].include?(Waha::RichNative::REPLY_SEPARATOR)

    description = option[:description]
    return unless description.nil? || line?(description, ROW_DESCRIPTION_MAX)

    row_id = Waha::RichNative.row_id(option[:id], @reference, max: ROW_ID_MAX)
    { title: option[:title], rowId: row_id, description: description }.compact
  end

  # O texto que abre a lista: o do chamador, ou o padrão no idioma da conta.
  def button
    @rich[:button].presence || I18n.t('waha.rich_payload.list_button', locale: @locale, default: I18n.t('waha.rich_payload.list_button'))
  end

  # ---- location ----
  def coordinates?
    coordinate?(@rich[:latitude], -90..90) && coordinate?(@rich[:longitude], -180..180)
  end

  def coordinate?(value, range)
    (value.is_a?(Integer) || value.is_a?(Float)) && value.finite? && range.cover?(value)
  end

  def location
    { latitude: @rich[:latitude], longitude: @rich[:longitude], title: location_title }
  end

  # O motor só tem um título no cartão: nome e endereço juntos, ou o padrão no idioma da conta.
  def location_title
    [@rich[:name], @rich[:address]].select { |part| part.is_a?(String) && part.strip.present? }.join(' - ').presence ||
      I18n.t('waha.rich_payload.location_title', locale: @locale, default: I18n.t('waha.rich_payload.location_title'))
  end

  # ---- contact ----
  # Sem `wa_id` o cartão vai sem ele, como na Meta (o aparelho não oferece "Conversar").
  def contact
    name = @rich[:name]
    phone = @rich[:phone]
    return unless name.is_a?(String) && name.strip.present? && phone.is_a?(String) && phone.strip.present?

    wa_id = @rich[:wa_id]
    { fullName: name, phoneNumber: phone, whatsappId: (wa_id if wa_id.is_a?(String) && wa_id.present?) }.compact
  end

  def line?(text, max)
    text.is_a?(String) && text.strip.present? && text.length <= max && LINE_BREAKS.none? { |line_break| text.include?(line_break) }
  end
end
