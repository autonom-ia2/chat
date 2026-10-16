class Messages::MarkdownRenderers::WhatsAppRenderer < Messages::MarkdownRenderers::BaseMarkdownRenderer
  FENCES = Messages::MarkdownRenderers::WhatsAppNewlines::FENCES
  TRIPLE_BACKTICKS = FENCES.first
  DELIMITERS = { emph: 1, strong: 2, strikethrough: 2 }.freeze

  # `source`: o mesmo texto entregue ao CommonMarker. As posições dos nós apontam para
  # ele: separa o bloco cercado (vira mono) do recuado (texto), conta as crases do código
  # em linha e acha marcador colado em letra ou número.
  def initialize(source)
    super()
    @list_item_number = 0
    @quote_depth = 0
    @source_lines = source.to_s.split("\n", -1)
  end

  def strong(node)
    wrap(node, '*')
  end

  def emph(node)
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

  def link(node)
    out(node.url)
  end

  def list(node)
    @list_type = node.list_type
    @list_item_number = @list_type == :ordered_list ? node.list_start : 0
    out(:children)
    cr
  end

  def list_item(_node)
    if @list_type == :ordered_list
      out("#{@list_item_number}. ", :children)
      @list_item_number += 1
    else
      out('- ', :children)
    end
    cr
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
