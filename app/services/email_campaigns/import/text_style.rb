# The text style a node inherits in an imported model (#1099) — size, color, family, weight, slant, line height and
# alignment — folded from the inline styles and presentational attributes of its ancestors, as a browser cascades
# them. The converter groups text by it and writes it onto mj-text. Immutable; no regex.
class EmailCampaigns::Import::TextStyle
  ATTRIBUTES = %i[font_size color font_family bold italic line_height align].freeze
  DEFAULTS = { font_size: nil, color: nil, font_family: nil, bold: false, italic: false, line_height: nil, align: nil }.freeze
  HEADINGS = { 'h1' => 32, 'h2' => 24, 'h3' => 19, 'h4' => 16, 'h5' => 13, 'h6' => 11 }.freeze
  FONT_SIZES = { '1' => 10, '2' => 13, '3' => 16, '4' => 18, '5' => 24, '6' => 32, '7' => 48 }.freeze
  BOLD = %w[bold bolder 600 700 800 900].freeze
  NOT_BOLD = %w[normal lighter 100 200 300 400 500].freeze
  BOLD_TAGS = %w[b strong h1 h2 h3 h4 h5 h6 th].freeze
  ITALIC_TAGS = %w[em i cite].freeze
  ALIGNS = %w[left center right justify].freeze
  ALIGN_TAGS = %w[p div td th h1 h2 h3 h4 h5 h6 center].freeze

  attr_reader(*ATTRIBUTES)

  def self.default
    new(font_size: 16.0, color: '#000000', align: 'left')
  end

  # px, % or a bare multiplier — what mj-text accepts; nil for anything else (normal, inherit, CSS smuggled in). In em
  # the number already is the multiplier of the letter (1.2em is 1.2, never 1.2 × 16); rem is of the page root, so it
  # is px (1.5rem is 24px whatever the letter).
  def self.line_height(value)
    text = EmailCampaigns::Import::StyleMap.plain(value).downcase
    return if text.empty?

    number = line_number(text)
    return if number.nil? || number <= 0
    return "#{number.round}px" if text.end_with?('px', 'rem')

    text.end_with?('%') ? "#{number.round}%" : number.round(2).to_s
  end

  # The number of a line height: em is the multiplier itself; px and rem come as px (StyleMap counts a rem as 16 px).
  def self.line_number(text)
    em = text.end_with?('em') && !text.end_with?('rem')
    EmailCampaigns::Import::StyleMap.px(em ? text.delete_suffix('em') : text.delete_suffix('%'))
  end

  # The style the content of `node` starts from: every element ancestor folded from the top.
  def self.inherited_for(node)
    node.ancestors.to_a.reverse.select(&:element?).reduce(default) { |style, ancestor| style.inherit(ancestor) }
  end

  def initialize(**attributes)
    unknown = attributes.keys - ATTRIBUTES
    raise ArgumentError, "unknown text style attributes #{unknown}" if unknown.any?

    values = DEFAULTS.merge(attributes)
    ATTRIBUTES.each { |name| instance_variable_set(:"@#{name}", values.fetch(name)) }
    freeze
  end

  def with(**changes)
    self.class.new(**to_h, **changes)
  end

  def to_h
    ATTRIBUTES.index_with { |name| public_send(name) }
  end

  def inherit(element)
    style = EmailCampaigns::Import::StyleMap.parse(element['style'])
    name = element.name
    with(font_size: size(style, element) || font_size, color: color_of(style, element) || color,
         font_family: family_of(style, element) || font_family, bold: bold_of(style, name), italic: italic_of(style, name),
         line_height: line_height_of(style) || line_height, align: align_of(style, element) || inherited_align(element))
  end

  # Paragraphs with the same key share one mj-text.
  def key
    [font_size.round, color, bold, italic, line_height, align, font_family.to_s.split(',').first.to_s.strip.downcase]
  end

  private

  def size(style, element)
    value = EmailCampaigns::Import::StyleMap.plain(style['font-size']).downcase
    return relative_size(value) if value.end_with?('%', 'em') && !value.end_with?('rem')
    return EmailCampaigns::Import::StyleMap.px(value) if value.present?
    return FONT_SIZES[element['size'].to_s.strip] if element.name == 'font'

    HEADINGS[element.name]
  end

  def relative_size(value)
    number = value.delete_suffix('%').delete_suffix('em').to_f
    value.end_with?('%') ? font_size * number / 100 : font_size * number
  end

  def color_of(style, element)
    EmailCampaigns::Import::StyleMap.color(style['color']) ||
      (element.name == 'font' ? EmailCampaigns::Import::StyleMap.color(element['color']) : nil)
  end

  def family_of(style, element)
    family = EmailCampaigns::Import::StyleMap.plain(style['font-family']).presence
    family || (element.name == 'font' ? element['face'].presence : nil)
  end

  def bold_of(style, name)
    weight = EmailCampaigns::Import::StyleMap.plain(style['font-weight']).downcase
    return true if BOLD.include?(weight)
    return false if NOT_BOLD.include?(weight)

    BOLD_TAGS.include?(name) || bold
  end

  def italic_of(style, name)
    slant = EmailCampaigns::Import::StyleMap.plain(style['font-style']).downcase
    return slant == 'italic' || slant == 'oblique' if slant.present?

    ITALIC_TAGS.include?(name) || italic
  end

  def line_height_of(style)
    self.class.line_height(style['line-height'])
  end

  # Email tables start their content on the left, whatever the cell around them centers.
  def inherited_align(element)
    element.name == 'table' ? 'left' : align
  end

  def align_of(style, element)
    value = EmailCampaigns::Import::StyleMap.plain(style['text-align']).downcase
    return value if ALIGNS.include?(value)
    return 'center' if element.name == 'center'

    attribute = element['align'].to_s.downcase
    attribute if ALIGN_TAGS.include?(element.name) && ALIGNS.include?(attribute)
  end
end
