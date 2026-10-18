# Linhas em branco seguidas viram {{PRESERVE_n_NEWLINES}} antes do CommonMarker (como no
# MarkdownRendererService#preserve_multiple_newlines), para o WhatsApp receber as linhas
# em branco que o atendente escreveu. Lá o marcador cola a linha seguinte na anterior;
# encostado numa cerca de código, isso desmontava o bloco (#1732). Aqui o marcador fica do
# lado de fora da cerca, o total de quebras é o mesmo depois da restauração, e dentro do
# bloco as linhas em branco ficam como estão.
class Messages::MarkdownRenderers::WhatsAppNewlines
  FENCES = ['```', '~~~'].freeze

  def self.preserve(content)
    new(content).preserve
  end

  def initialize(content)
    @lines = content.split("\n", -1)
    @open_fence = nil
  end

  def preserve
    result = @lines.first.to_s.dup
    track_fence(@lines.first.to_s)
    index = 1
    while index < @lines.length
      newlines = 1
      while @open_fence.nil? && @lines[index].empty? && index < @lines.length - 1
        newlines += 1
        index += 1
      end
      result << joint(@lines[index - newlines], @lines[index], newlines)
      track_fence(@lines[index])
      index += 1
    end
    result
  end

  private

  # `line` depois de `newlines` quebras, vindo de `previous`.
  def joint(previous, line, newlines)
    return "\n#{line}" if newlines == 1

    closes = !fence(previous).nil?
    opens = !fence(line).nil?
    return "\n#{placeholder(newlines - 2)}\n#{line}" if closes && opens
    return "\n#{placeholder(newlines - 1)}#{line}" if closes
    return "#{placeholder(newlines - 1)}\n#{line}" if opens

    "#{placeholder(newlines)}#{line}"
  end

  def placeholder(count)
    "{{PRESERVE_#{count}_NEWLINES}}"
  end

  # Abre numa cerca; fecha na cerca do mesmo caractere, do mesmo tamanho ou maior e sem info.
  def track_fence(line)
    current = fence(line)
    return if current.nil?
    return @open_fence = current if @open_fence.nil?

    @open_fence = nil if closes_open_fence?(current, line)
  end

  def closes_open_fence?(current, line)
    current[0] == @open_fence[0] && current.length >= @open_fence.length &&
      line.lstrip.delete_prefix(current).strip.empty?
  end

  # Os caracteres da cerca no começo da linha, ou nil. Aceita recuo (cerca dentro de item
  # de lista); o CommonMarker é quem decide depois o que é bloco.
  def fence(line)
    stripped = line.lstrip
    return unless stripped.start_with?(*FENCES)

    run = stripped[0] * stripped.each_char.take_while { |char| char == stripped[0] }.size
    # ```x``` numa linha só é código em linha, não cerca.
    return if run.start_with?('`') && stripped.delete_prefix(run).include?('`')

    run
  end
end
