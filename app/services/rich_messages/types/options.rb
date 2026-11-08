# Opções para o cliente tocar (chat#1473, P3): botões de resposta ou lista.
#   { "type": "options", "header": "Próximo passo", "footer": "Toque em uma opção.", "button": "Ver unidades",
#     "options": [{ "id": "agendar", "title": "Agendar visita", "description": "Na unidade mais perto" }] }
#   ou, no lugar de `options`, "sections": [{ "title": "Atendimento", "options": [...] }]
# Só `options` OU `sections`; `header`, `footer` e `description` são opcionais. Sai como LISTA quando vêm seções,
# mais de 3 opções ou alguma descrição (o botão de resposta não mostra nem seção nem descrição); senão, como BOTÕES.
# `button` (o texto que abre a lista) é OBRIGATÓRIO na lista e ignorado nos botões: o painel não inventa texto para
# o cliente, porque não sabe o idioma da conversa.
# Limites da Meta: até 3 botões (título 20, id 256, corpo 1024, títulos diferentes entre si); lista com até 10
# opções no total em até 10 seções (título 24, id 200, descrição 72, título de seção 24, botão 20, corpo 4096);
# cabeçalho de texto e rodapé até 60. Os ids não se repetem. Títulos, cabeçalho, rodapé e botão em uma linha só.
# Toda seção sai com título (a página da Meta o dá como obrigatório): com mais de uma seção o chamador manda o de
# cada uma; a seção única sem título (inclusive a das opções soltas) sai com o texto do `button`, que cabe (20 <= 24).
# Cabeçalho de imagem não entra nesta entrega.
class RichMessages::Types::Options
  BUTTONS_MAX = 3
  OPTIONS_MAX = 10
  SECTIONS_MAX = 10
  EDGE_MAX = 60
  SECTION_TITLE_MAX = 24
  DESCRIPTION_MAX = 72
  LIST_BUTTON_MAX = 20
  BUTTONS = { body: 1024, title: 20, id: 256 }.freeze
  LIST = { body: 4096, title: 24, id: 200 }.freeze
  # Quebras de linha que o WhatsApp pode desenhar: \n, \r, tabulação vertical, NEL (U+0085), separador de linha
  # (U+2028) e de parágrafo (U+2029).
  LINE_BREAKS = ["\n", "\r", "\v", "\u0085", "\u2028", "\u2029"].freeze

  BODY_BLANK = 'As opções precisam de um texto na mensagem.'.freeze
  BUTTONS_BODY_TOO_LONG = "O texto da mensagem com botões de opção passa de #{BUTTONS[:body]} caracteres.".freeze
  LIST_BODY_TOO_LONG = "O texto da mensagem com lista de opções passa de #{LIST[:body]} caracteres.".freeze
  OPTIONS_AND_SECTIONS = 'As opções vieram soltas e em seções ao mesmo tempo: use só um dos dois.'.freeze
  NO_OPTIONS = 'A mensagem de opções está sem opções.'.freeze
  TOO_MANY_OPTIONS = "A mensagem de opções passa de #{OPTIONS_MAX} opções.".freeze
  TOO_MANY_SECTIONS = "A lista de opções passa de #{SECTIONS_MAX} seções.".freeze
  SECTION_INVALID = 'Cada seção da lista de opções precisa trazer as suas opções.'.freeze
  SECTION_TITLE_INVALID = 'Com mais de uma seção, cada seção da lista precisa de um título de até ' \
                          "#{SECTION_TITLE_MAX} caracteres, em uma linha só.".freeze
  OPTION_INVALID = 'Cada opção precisa de um identificador e de um título, em texto.'.freeze
  OPTION_ID_REPEATED = 'Duas opções têm o mesmo identificador.'.freeze
  TITLE_MULTILINE = 'O título de cada opção precisa ficar em uma linha só.'.freeze
  BUTTON_TITLE_TOO_LONG = "O título de um botão de opção passa de #{BUTTONS[:title]} caracteres.".freeze
  BUTTON_ID_TOO_LONG = "O identificador de um botão de opção passa de #{BUTTONS[:id]} caracteres.".freeze
  BUTTON_TITLE_REPEATED = 'Dois botões de opção têm o mesmo título.'.freeze
  ROW_TITLE_TOO_LONG = "O título de uma opção da lista passa de #{LIST[:title]} caracteres.".freeze
  ROW_ID_TOO_LONG = "O identificador de uma opção da lista passa de #{LIST[:id]} caracteres.".freeze
  DESCRIPTION_INVALID = "A descrição de uma opção precisa ser um texto de até #{DESCRIPTION_MAX} caracteres, em uma linha só.".freeze
  HEADER_INVALID = "O cabeçalho das opções precisa ser um texto de até #{EDGE_MAX} caracteres, em uma linha só.".freeze
  FOOTER_INVALID = "O rodapé das opções precisa ser um texto de até #{EDGE_MAX} caracteres, em uma linha só.".freeze
  LIST_BUTTON_INVALID = 'A lista de opções precisa do texto do botão que a abre (button), com até ' \
                        "#{LIST_BUTTON_MAX} caracteres, em uma linha só.".freeze

  def initialize(payload)
    @header = payload['header']
    @footer = payload['footer']
    @button = payload['button']
    @options = payload['options']
    @sections = payload['sections']
  end

  def error_for(body)
    shape_error || body_error(body) || section_titles_error || options_error ||
      text_error(@header, EDGE_MAX, HEADER_INVALID) || text_error(@footer, EDGE_MAX, FOOTER_INVALID) ||
      list_button_error
  end

  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-reply-buttons-messages
  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-list-messages
  def whatsapp_cloud_payload(body)
    {
      type: 'interactive',
      interactive: {
        type: list? ? 'list' : 'button',
        header: (@header && { type: 'text', text: @header }),
        body: { text: body },
        footer: (@footer && { text: @footer }),
        action: list? ? list_action : buttons_action
      }.compact
    }
  end

  # As opções numeradas, uma por linha, na ordem em que o cliente as veria; título da seção numa linha própria e a
  # descrição depois de " - ". Cabeçalho, rodapé e botão da lista não entram: são moldura do cartão.
  def fallback_text(_body)
    groups.each_with_index.flat_map do |(title, options), index|
      first = groups.first(index).sum { |(_previous_title, previous)| previous.size } + 1
      lines = options.map.with_index(first) { |option, number| "#{number}. #{option_text(option)}" }
      title.present? ? [title, *lines] : lines
    end.join("\n")
  end

  # A régua dos textos do cartão (texto preenchido, até `max`, em uma linha), também para quem monta o formato antes
  # de mandar (o agente, #1479: o botão da lista que não cabe vira o padrão em vez de derrubar a lista).
  def self.fits?(text, max)
    filled_text?(text) && text.length <= max && one_line?(text)
  end

  def self.filled_text?(value)
    value.is_a?(String) && value.strip.present?
  end

  def self.one_line?(text)
    LINE_BREAKS.none? { |line_break| text.include?(line_break) }
  end

  private

  # [título da seção, opções]; com `options` soltas, uma seção sem título.
  def groups
    @groups ||= @sections ? @sections.map { |section| [section['title'], section['options']] } : [[nil, @options]]
  end

  def all_options
    groups.flat_map(&:last)
  end

  def option_text(option)
    [option['title'], option['description']].compact.join(' - ')
  end

  def list?
    @sections.present? || all_options.size > BUTTONS_MAX || all_options.any? { |option| !option['description'].nil? }
  end

  def limits
    list? ? LIST : BUTTONS
  end

  def buttons_action
    { buttons: all_options.map { |option| { type: 'reply', reply: { id: option['id'], title: option['title'] } } } }
  end

  def list_action
    sections = groups.map do |title, options|
      rows = options.map { |option| { id: option['id'], title: option['title'], description: option['description'] }.compact }
      { title: title.presence || @button, rows: rows }
    end
    { button: @button, sections: sections }
  end

  # A forma da entrada, antes de qualquer outra regra: depois dela `groups` só tem listas de objetos.
  def shape_error
    return OPTIONS_AND_SECTIONS if @options && @sections
    return sections_shape_error if @sections
    return NO_OPTIONS unless filled_list?(@options)

    options_count_error
  end

  def sections_shape_error
    return SECTION_INVALID unless filled_list?(@sections)
    return TOO_MANY_SECTIONS if @sections.size > SECTIONS_MAX
    return SECTION_INVALID unless @sections.all? { |section| section.is_a?(Hash) && filled_list?(section['options']) }

    options_count_error
  end

  def options_count_error
    return TOO_MANY_OPTIONS if all_options.size > OPTIONS_MAX

    OPTION_INVALID unless all_options.all?(Hash)
  end

  def filled_list?(value)
    value.is_a?(Array) && value.any?
  end

  def body_error(body)
    return BODY_BLANK if body.blank?

    (list? ? LIST_BODY_TOO_LONG : BUTTONS_BODY_TOO_LONG) if body.length > limits[:body]
  end

  # Com uma seção só o título pode faltar (sai o texto do botão da lista no lugar); com mais de uma, cada seção
  # precisa do seu.
  def section_titles_error
    return unless @sections

    titles = @sections.pluck('title')
    titles = titles.compact_blank if @sections.one?
    SECTION_TITLE_INVALID unless titles.all? { |title| fits?(title, SECTION_TITLE_MAX) }
  end

  def options_error
    all_options.lazy.filter_map { |option| option_error(option) }.first || repetition_error
  end

  def option_error(option)
    return OPTION_INVALID unless filled_text?(option['id']) && filled_text?(option['title'])
    return TITLE_MULTILINE unless one_line?(option['title'])

    length_error(option) || text_error(option['description'], DESCRIPTION_MAX, DESCRIPTION_INVALID)
  end

  def length_error(option)
    return (list? ? ROW_TITLE_TOO_LONG : BUTTON_TITLE_TOO_LONG) if option['title'].length > limits[:title]

    (list? ? ROW_ID_TOO_LONG : BUTTON_ID_TOO_LONG) if option['id'].length > limits[:id]
  end

  def repetition_error
    return OPTION_ID_REPEATED unless all_options.pluck('id').uniq.size == all_options.size

    BUTTON_TITLE_REPEATED unless list? || all_options.pluck('title').uniq.size == all_options.size
  end

  # O botão que abre a lista: obrigatório na lista, ignorado nos botões.
  def list_button_error
    LIST_BUTTON_INVALID if list? && !fits?(@button, LIST_BUTTON_MAX)
  end

  # Campo opcional de texto: ausente, ou texto preenchido de até `max` caracteres em uma linha.
  def text_error(text, max, error)
    error unless text.nil? || fits?(text, max)
  end

  def fits?(text, max)
    self.class.fits?(text, max)
  end

  def filled_text?(value)
    self.class.filled_text?(value)
  end

  def one_line?(text)
    self.class.one_line?(text)
  end
end
