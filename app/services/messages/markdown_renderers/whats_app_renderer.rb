class Messages::MarkdownRenderers::WhatsAppRenderer < Messages::MarkdownRenderers::BaseMarkdownRenderer
  FENCES = ['```', '~~~'].freeze
  MIN_FENCE = 3

  # Linhas em branco seguidas viram {{PRESERVE_n_NEWLINES}} (MarkdownRendererService), que
  # cola a linha seguinte na anterior. Encostado numa cerca de código, isso desmontava o
  # bloco (#1732). Aqui o marcador fica do lado de fora da cerca, e o total de quebras é o
  # mesmo depois da restauração; dentro do bloco as linhas em branco ficam como estão.
  def self.preserve_newlines(content)
    lines = content.split("\n", -1)
    result = lines.first.to_s.dup
    in_fence = fence_state(lines.first.to_s, false)
    index = 1
    while index < lines.length
      newlines = 1
      while !in_fence && lines[index].empty? && index < lines.length - 1
        newlines += 1
        index += 1
      end
      result << joint(lines[index - newlines], lines[index], newlines)
      in_fence = fence_state(lines[index], in_fence)
      index += 1
    end
    result
  end

  # Junta `line` ao texto depois de `newlines` quebras, vindo de `previous`.
  def self.joint(previous, line, newlines)
    return "\n#{line}" if newlines == 1

    closes = fence_line?(previous)
    opens = fence_line?(line)
    return "\n#{placeholder(newlines - 2)}\n#{line}" if closes && opens
    return "\n#{placeholder(newlines - 1)}#{line}" if closes
    return "#{placeholder(newlines - 1)}\n#{line}" if opens

    "#{placeholder(newlines)}#{line}"
  end

  def self.placeholder(count)
    "{{PRESERVE_#{count}_NEWLINES}}"
  end

  # Estado da cerca depois de `line`: abre numa cerca com ou sem info, fecha só na cerca pura.
  def self.fence_state(line, in_fence)
    return in_fence unless fence_line?(line)
    return false if in_fence && fence_info(line).strip.empty?

    true
  end

  def self.fence_line?(line)
    stripped = line.lstrip
    return false unless stripped.start_with?(*FENCES)

    # ```x``` numa linha só é código em linha, não cerca.
    !(stripped.start_with?('`') && fence_info(line).include?('`'))
  end

  def self.fence_info(line)
    stripped = line.lstrip
    stripped[stripped.each_char.take_while { |char| char == stripped[0] }.size..].to_s
  end

  # `source`: o mesmo texto entregue ao CommonMarker. Serve só para separar o bloco
  # de código cercado (``` ou ~~~, vira mono no WhatsApp) do recuado por 4 espaços,
  # que segue como texto simples (recuo acidental não vira mono).
  def initialize(source = '')
    super()
    @list_item_number = 0
    @quote_depth = 0
    @source_lines = source.to_s.split("\n", -1)
  end

  def strong(_node)
    out('*', :children, '*')
  end

  def emph(_node)
    out('_', :children, '_')
  end

  def strikethrough(_node)
    out('~', :children, '~')
  end

  # ```x``` escrito numa linha é mono no WhatsApp; `x` é código em linha. O CommonMarker
  # trata os dois como código em linha, então a quantidade de crases vem do texto.
  def code(node)
    ticks = triple_backticks?(node) ? FENCES.first : '`'
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

    out("```#{node.string_content.chomp}```")
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

  def fenced?(node)
    starts_with_source?(node, *FENCES)
  end

  # A posição do código em linha aponta o conteúdo; as crases ficam logo antes.
  def triple_backticks?(node)
    line = @source_lines[node.sourcepos[:start_line] - 1].to_s
    start = node.sourcepos[:start_column] - 1 - MIN_FENCE
    start >= 0 && line[start, MIN_FENCE] == FENCES.first
  end

  def starts_with_source?(node, *prefixes)
    line = @source_lines[node.sourcepos[:start_line] - 1].to_s
    line[(node.sourcepos[:start_column] - 1)..].to_s.lstrip.start_with?(*prefixes)
  end
end
