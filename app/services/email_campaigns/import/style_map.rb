# Inline CSS helpers for the importer (#1099): declarations as an ordered hash, px lengths, hex colors and paddings.
# Plain string methods — no regex.
module EmailCampaigns::Import::StyleMap
  HEX = '0123456789abcdef'.freeze
  NUMBER = '0123456789.-'.freeze
  IMPORTANT = '!important'.freeze
  NAMED = { 'white' => '#ffffff', 'black' => '#000000', 'red' => '#ff0000', 'gray' => '#808080', 'grey' => '#808080',
            'silver' => '#c0c0c0', 'navy' => '#000080', 'blue' => '#0000ff', 'green' => '#008000', 'orange' => '#ffa500' }.freeze
  SIDES = %w[top right bottom left].freeze
  UNITS = { '' => 1.0, 'px' => 1.0, 'pt' => 4 / 3.0, 'em' => 16.0, 'rem' => 16.0 }.freeze

  module_function

  def parse(style)
    style.to_s.split(';').each_with_object({}) do |declaration, out|
      name, value = declaration.split(':', 2)
      next if value.nil?

      key = name.strip.downcase
      out[key] = value.strip unless key.empty? || value.strip.empty?
    end
  end

  def dump(declarations)
    declarations.map { |property, value| "#{property}:#{value}" }.join(';')
  end

  def important?(value)
    value.to_s.delete(' ').downcase.end_with?(IMPORTANT)
  end

  def plain(value)
    text = value.to_s.strip
    return text unless important?(text)

    text[0...text.downcase.rindex('!')].strip
  end

  # A length in px (px, pt, em or a bare number); nil for %, auto and anything else.
  def px(value)
    text = plain(value).downcase
    digits = text.each_char.take_while { |char| NUMBER.include?(char) }.join
    return if digits.empty? || digits == '.' || digits == '-'

    factor = UNITS[text[digits.length..].strip]
    factor && (Float(digits) * factor)
  rescue ArgumentError
    nil
  end

  # '#rrggbb' for hex, rgb() and a few names; nil for anything else (transparent, gradients, variables).
  def color(value)
    text = plain(value).downcase
    return NAMED[text] if NAMED.key?(text)
    return hex(text) if text.start_with?('#')

    rgb(text) if text.start_with?('rgb')
  end

  def hex(text)
    digits = text.delete_prefix('#')
    digits = digits.chars.map { |char| char * 2 }.join if digits.length == 3
    "##{digits}" if digits.length == 6 && digits.each_char.all? { |char| HEX.include?(char) }
  end

  # rgb(r, g, b) or rgba(...) with a visible alpha; channels as numbers or percentages.
  def rgb(text)
    parts = text.split('(', 2).last.to_s.split(')').first.to_s.split(',').map(&:strip)
    return unless rgb_parts?(parts)

    channels = parts.first(3).map { |part| channel(part) }
    "##{channels.map { |channel| channel.to_s(16).rjust(2, '0') }.join}" if channels.all? { |channel| channel.between?(0, 255) }
  end

  # Three channels, and an alpha (when given) that is not fully transparent.
  def rgb_parts?(parts)
    parts.size.between?(3, 4) && parts.fetch(3, '1').to_f.positive?
  end

  def channel(part)
    part.end_with?('%') ? (part.to_f * 2.55).round : part.to_i
  end

  # The first color named in a shorthand such as `background: url(x) center #1f3a5f`.
  def first_color(shorthand)
    plain(shorthand).split.each do |token|
      found = color(token.delete_suffix(','))
      return found if found
    end
    nil
  end

  # CSS padding shorthand (1 to 4 lengths) as four px values, "T R B L"; nil when any part is not a length.
  def padding(value)
    parts = plain(value).split.map { |part| px(part) }
    return if parts.empty? || parts.size > 4 || parts.any?(&:nil?)

    top, right, bottom, left = expand(parts)
    [top, right, bottom, left].map { |part| "#{part.round}px" }.join(' ')
  end

  # The padding of a declaration hash: the shorthand, overridden side by side by padding-top/right/bottom/left.
  def padding_of(declarations)
    sides = SIDES.map { |side| px(declarations["padding-#{side}"].to_s) }
    base = padding(declarations['padding'].to_s)
    return base if sides.none?

    values = (base || '0 0 0 0').split.map { |part| px(part) }
    values.zip(sides).map { |value, side| "#{(side || value).round}px" }.join(' ')
  end

  def expand(parts)
    case parts.size
    when 1 then parts * 4
    when 2 then parts + parts
    when 3 then [parts[0], parts[1], parts[2], parts[1]]
    else parts
    end
  end
end
