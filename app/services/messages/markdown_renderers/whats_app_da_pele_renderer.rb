# O WhatsApp com a pele ligada (#1702, #1732): o texto sai no formato que o app mostra. Sem a pele, o
# envio segue o WhatsAppRenderer do Chatwoot, sem mudança nenhuma.
class Messages::MarkdownRenderers::WhatsAppDaPeleRenderer < Messages::MarkdownRenderers::WhatsAppRenderer
  FENCES = Messages::MarkdownRenderers::WhatsAppNewlines::FENCES
  TRIPLE_BACKTICKS = FENCES.first
  DELIMITERS = { emph: 1, strong: 2, strikethrough: 2 }.freeze

  # `source`: o mesmo texto entregue ao CommonMarker. As posições dos nós apontam para
  # ele: separa o bloco cercado (vira mono) do recuado (texto), conta as crases do código
  # em linha e acha marcador colado em letra ou número.
  # `automatico`: texto de robô, IA ou envio automático (Messages::EnvioAutomatico), que
  # escreve no dialeto do WhatsApp: *x* é negrito, como **x**. O editor grava itálico como
  # *x*, então para a pessoa digitando no painel *x* segue itálico.
  def initialize(source, automatico: false)
    super()
    @quote_depth = 0
    @bold_depth = 0
    @automatico = automatico
    @source_lines = source.to_s.split("\n", -1)
  end

  def strong(node)
    bold(node)
  end

  def emph(node)
    return bold(node) if @automatico && delimiter_of(node) == '*'

    wrap(node, '_')
  end

  def strikethrough(node)
    wrap(node, '~')
  end

  # ```x``` escrito numa linha é mono no WhatsApp; `x` é código em linha. O CommonMarker
  # trata os dois como código em linha, então a quantidade de crases vem do texto.
  def code(node)
    ticks = triple_backticks?(node) ? TRIPLE_BACKTICKS : '`'
    out(ticks, node.string_content, ticks)
  end

  # No WhatsApp a citação vale por linha: cada linha da citação leva o "> ".
  def blockquote(_node)
    @quote_depth += 1
    out('> ', :children)
    @quote_depth -= 1
    cr
  end

  def paragraph(node)
    out(quote_prefix) if @quote_depth.positive? && node.previous
    super
  end

  def code_block(node)
    return out(node.string_content) unless fenced?(node)
    return if node.string_content.strip.empty?

    out("#{TRIPLE_BACKTICKS}#{node.string_content.chomp}#{TRIPLE_BACKTICKS}")
    cr
  end

  def softbreak(_node)
    out("\n", quote_prefix)
  end

  def linebreak(_node)
    out("\n", quote_prefix)
  end

  private

  def quote_prefix
    '> ' * @quote_depth
  end

  # Negrito dentro de negrito (***x*** do robô) fica um negrito só: *x*.
  def bold(node)
    return out(:children) if @bold_depth.positive?

    @bold_depth += 1
    wrap(node, '*')
    @bold_depth -= 1
  end

  def delimiter_of(node)
    byte_slice(node.sourcepos[:start_line], node.sourcepos[:start_column], 1)
  end

  # No WhatsApp, marcador grudado em letra ou número (2*3*4) não formata. O CommonMarker
  # aceita; então o texto sai com os marcadores como foram escritos.
  def wrap(node, marker)
    return out(marker, :children, marker) unless intraword?(node)

    delimiter = byte_slice(node.sourcepos[:start_line], node.sourcepos[:start_column], DELIMITERS[node.type])
    out(delimiter, :children, delimiter)
  end

  def intraword?(node)
    pos = node.sourcepos
    before = byte_slice(pos[:start_line], 1, pos[:start_column] - 1)[-1]
    after = byte_slice(pos[:end_line], pos[:end_column] + 1, nil)[0]
    alnum?(before) || alnum?(after)
  end

  def alnum?(char)
    return false if char.nil?

    ('0'..'9').cover?(char) || char.downcase != char.upcase
  end

  # Bloco cercado: a linha de início é a cerca, que não faz parte do conteúdo. No recuado
  # a linha de início já é o conteúdo, mesmo que comece com ```.
  def fenced?(node)
    first_line = byte_slice(node.sourcepos[:start_line], node.sourcepos[:start_column], nil)
    first_line.lstrip.start_with?(*FENCES) && node.string_content.split("\n").first.to_s != first_line
  end

  # A posição do código em linha aponta o conteúdo; as crases ficam logo antes.
  def triple_backticks?(node)
    start = node.sourcepos[:start_column] - TRIPLE_BACKTICKS.length
    start >= 1 && byte_slice(node.sourcepos[:start_line], start, TRIPLE_BACKTICKS.length) == TRIPLE_BACKTICKS
  end

  # As colunas do CommonMarker contam bytes (1 = primeiro byte da linha).
  def byte_slice(line_number, column, length)
    line = @source_lines[line_number - 1].to_s
    from = column - 1
    slice = length ? line.byteslice(from, length) : line.byteslice(from..)
    slice.to_s.scrub
  end
end
