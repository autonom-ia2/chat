# Índice das regras CSS de uma página (#1076), montado com `css_parser` (sem seguir @import: a busca é só
# do SafeFetch). Guarda as declarações por tag, por classe e por id quando o seletor é simples, as
# variáveis CSS (`--nome`) e as regras de botão; responde o "estilo aproximado" de um elemento juntando
# tag < classes < id < style inline. Não é uma cascata completa — é o bastante para achar cores e fontes.
class BrandKits::Extraction::StylesheetIndex
  TAGS = %w[html body h1 h2 h3 a button p].freeze
  ROOT_SELECTORS = %w[:root html body :host].freeze
  BUTTON_HINTS = %w[btn button cta].freeze
  SPECIAL_SELECTOR_CHARS = " .:#[]>+~,()*\n\t".freeze
  MAX_RULES = 20_000
  MAX_VAR_DEPTH = 8
  SCREEN_MEDIA = %i[all screen].freeze

  attr_reader :button_rules

  def initialize(stylesheets)
    @by_tag = Hash.new { |hash, key| hash[key] = {} }
    @by_class = Hash.new { |hash, key| hash[key] = {} }
    @by_id = Hash.new { |hash, key| hash[key] = {} }
    @variables = {}
    @root_variables = {}
    @button_rules = []
    @rules = 0
    stylesheets.each { |css| index(css) }
  end

  # Declarações (propriedade => valor com var() resolvido) que valem para o elemento Nokogiri.
  def style_for(node)
    matching_rules(node).reduce({}) { |style, values| style.merge(values) }.transform_values { |value| resolve(value) }
  end

  def root_style(name)
    @by_tag[name].transform_values { |value| resolve(value) }
  end

  def variables
    @variables.merge(@root_variables).transform_values { |value| resolve(value) }
  end

  # Substitui var(--x, reserva) pelo valor da variável (ou a reserva), até MAX_VAR_DEPTH níveis.
  def resolve(value, depth = 0)
    text = value.to_s
    start = text.index('var(')
    return text if start.nil? || depth > MAX_VAR_DEPTH

    finish = closing_paren(text, start + 3)
    return text if finish.nil?

    name, fallback = text[(start + 4)...finish].split(',', 2).map(&:strip)
    replacement = @root_variables[name] || @variables[name] || fallback.to_s
    resolve(text[0...start] + replacement + text[(finish + 1)..], depth + 1)
  end

  private

  def index(css)
    parser = CssParser::Parser.new(import: false, absolute_paths: false)
    parser.add_block!(unwrap_layers(css.to_s.b).force_encoding(Encoding::UTF_8).scrub)
    parser.each_rule_set do |rule_set, media_types|
      next unless media_types.all? { |media| SCREEN_MEDIA.include?(media) }

      rule_set.each_selector { |selector, _declarations, _specificity| add_rule(selector.strip, rule_set) }
    end
  rescue CssParser::Error, ArgumentError, Encoding::CompatibilityError => e
    Rails.logger.info("[BrandKits] stylesheet skipped: #{e.class.name}")
  end

  def add_rule(selector, rule_set)
    @rules += 1
    return if @rules > MAX_RULES

    values = rule_values(rule_set)
    collect_variables(selector, values)
    @button_rules << values if button_selector?(selector)
    store(selector, values.reject { |property, _value| property.start_with?('--') })
  end

  # Regras na ordem da especificidade aproximada: tag < classes < id < style inline.
  def matching_rules(node)
    rules = [@by_tag.fetch(node.name, {})]
    rules.concat(node['class'].to_s.split.map { |name| @by_class.fetch(name, {}) })
    rules << @by_id.fetch(node['id'].to_s, {})
    rules << declarations(node['style']) if node['style'].present?
    rules
  end

  def store(selector, values)
    return if values.empty?

    target, name = bucket(selector)
    target[name].merge!(values) if name
  end

  def bucket(selector)
    return [@by_tag, selector.delete_prefix(':')] if ROOT_SELECTORS.include?(selector) || TAGS.include?(selector)
    return [@by_class, simple_name(selector[1..])] if selector.start_with?('.')
    return [@by_id, simple_name(selector[1..])] if selector.start_with?('#')

    [nil, nil]
  end

  def collect_variables(selector, values)
    values.each do |property, value|
      next unless property.start_with?('--')

      target = ROOT_SELECTORS.include?(selector) ? @root_variables : @variables
      target[property] = value unless target.key?(property) && target.equal?(@variables)
    end
  end

  def button_selector?(selector)
    return true if selector == 'button'

    lowered = selector.downcase
    lowered.exclude?(':') && BUTTON_HINTS.any? { |hint| lowered.include?(hint) }
  end

  def rule_values(rule_set)
    values = {}
    rule_set.each_declaration { |property, value, _important| values[property.to_s.downcase] = value.to_s.strip }
    values
  end

  def declarations(style)
    rule_set = CssParser::RuleSet.new(selectors: 'inline', block: style.to_s)
    rule_values(rule_set)
  rescue CssParser::Error, ArgumentError
    {}
  end

  # Nome de classe/id de um seletor simples, desfazendo os escapes do CSS (`.bg-\[\#0B243F\]` → `bg-[#0B243F]`).
  # Devolve nil se o seletor tiver qualquer parte além do nome (pseudo-classe, descendente, atributo…).
  def simple_name(text)
    name = +''
    chars = text.chars
    index = 0
    while index < chars.length
      char = chars[index]
      if char == '\\'
        escaped, index = unescape(chars, index + 1)
        name << escaped
        next
      end
      return nil if SPECIAL_SELECTOR_CHARS.include?(char)

      name << char
      index += 1
    end
    name.presence
  end

  def unescape(chars, index)
    digits = +''
    while index < chars.length && digits.length < 6 && BrandKits::Color::HEX_DIGITS.include?(chars[index].downcase)
      digits << chars[index]
      index += 1
    end
    return [chars[index].to_s, index + 1] if digits.empty?

    index += 1 if chars[index] == ' '
    [[digits.to_i(16)].pack('U'), index]
  end

  # O css_parser não conhece `@layer` (Tailwind 4 põe tudo dentro de `@layer theme{…}`) e perde a primeira
  # regra de cada camada. A camada não muda o que procuramos: `@layer a{X}` vira `X`; `@layer a, b;` some.
  def unwrap_layers(css)
    output = +''
    position = 0
    while (start = css.index('@layer', position))
      output << css[position...start]
      brace = css.index('{', start)
      semicolon = css.index(';', start)
      if brace.nil? || (semicolon && semicolon < brace)
        position = semicolon ? semicolon + 1 : css.length
        next
      end
      finish = closing_brace(css, brace)
      output << unwrap_layers(css[(brace + 1)...finish].to_s)
      position = finish ? finish + 1 : css.length
    end
    output << css[position..].to_s
  end

  def closing_brace(text, open_index)
    depth = 0
    (open_index...text.length).each do |index|
      depth += 1 if text[index] == '{'
      depth -= 1 if text[index] == '}'
      return index if depth.zero?
    end
    nil
  end

  def closing_paren(text, open_index)
    depth = 0
    (open_index...text.length).each do |index|
      depth += 1 if text[index] == '('
      depth -= 1 if text[index] == ')'
      return index if depth.zero?
    end
    nil
  end
end
