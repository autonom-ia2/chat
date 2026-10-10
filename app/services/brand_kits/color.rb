# Cores da identidade visual (#1076). Leitura das notações que uma folha de estilo usa e a matemática
# de contraste do WCAG, portada do Bio (`src/lib/brand/appearance.ts`). Sem expressão regular: cada
# notação é lida com métodos de String.
module BrandKits::Color
  HEX_DIGITS = '0123456789abcdef'.freeze
  WHITE = '#ffffff'.freeze
  DARK_INK = '#0a1628'.freeze
  NAMED = { 'white' => WHITE, 'black' => '#000000' }.freeze
  # Diferença entre o maior e o menor canal abaixo da qual a cor é um cinza (branco, preto, grafite).
  NEUTRAL_CHROMA = 24
  TEXT_CONTRAST = 4.5

  module_function

  # '#RRGGBB' minúsculo, ou nil quando a cor é translúcida, relativa (var/lab/currentColor) ou malformada.
  def parse(value)
    text = value.to_s.downcase.delete_suffix('!important').strip
    return NAMED[text] if NAMED.key?(text)
    return parse_hex(text.delete_prefix('#')) if text.start_with?('#')
    return parse_rgb(text) if text.start_with?('rgb(', 'rgba(') && text.end_with?(')')

    nil
  end

  def hex?(value)
    value.is_a?(String) && value.length == 7 && value.start_with?('#') && hex_digits?(value[1..].downcase)
  end

  def rgb(hex)
    [1, 3, 5].map { |index| hex[index, 2].to_i(16) }
  end

  def luminance(hex)
    red, green, blue = rgb(hex).map do |channel|
      value = channel / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end

  def contrast(foreground, background)
    first = luminance(foreground)
    second = luminance(background)
    ([first, second].max + 0.05) / ([first, second].min + 0.05)
  end

  def readable_ink(background)
    contrast(WHITE, background) > contrast(DARK_INK, background) ? WHITE : DARK_INK
  end

  # Texto de botão sobre `background`: branco se passa 4,5:1; senão a tinta da marca; senão o melhor dos dois neutros.
  def text_on(background, ink:)
    return WHITE if contrast(WHITE, background) >= TEXT_CONTRAST
    return ink if hex?(ink) && contrast(ink, background) >= TEXT_CONTRAST

    readable_ink(background)
  end

  def composite(front, back, alpha)
    front_rgb = rgb(front)
    back_rgb = rgb(back)
    channels = front_rgb.each_with_index.map { |channel, index| ((channel * alpha) + (back_rgb[index] * (1 - alpha))).round }
    "##{channels.map { |channel| channel.to_s(16).rjust(2, '0') }.join}"
  end

  def chroma(hex)
    channels = rgb(hex)
    channels.max - channels.min
  end

  def neutral?(hex)
    chroma(hex) < NEUTRAL_CHROMA
  end

  # Matiz em graus (0–360); só faz sentido para cor não neutra.
  def hue(hex)
    red, green, blue = rgb(hex).map { |channel| channel / 255.0 }
    max = [red, green, blue].max
    delta = max - [red, green, blue].min
    return 0.0 if delta.zero?

    degrees = if max == red then ((green - blue) / delta) % 6
              elsif max == green then ((blue - red) / delta) + 2
              else
                ((red - green) / delta) + 4
              end
    (degrees * 60) % 360
  end

  def hue_distance(first, second)
    distance = (hue(first) - hue(second)).abs
    [distance, 360 - distance].min
  end

  def parse_hex(digits)
    return nil unless hex_digits?(digits)

    case digits.length
    when 3 then "##{digits.chars.map { |digit| digit * 2 }.join}"
    when 6 then "##{digits}"
    when 8 then digits.end_with?('ff') ? "##{digits[0, 6]}" : nil
    end
  end

  def parse_rgb(text)
    inner = text.delete_prefix('rgba(').delete_prefix('rgb(').delete_suffix(')')
    parts = inner.tr(',/', '  ').split
    return nil unless opaque_parts?(parts)

    channels = parts.first(3).map { |part| integer_channel(part) }
    return nil if channels.any?(&:nil?)

    "##{channels.map { |channel| channel.to_s(16).rjust(2, '0') }.join}"
  end

  # Três canais, ou três canais e alfa 1 (cor translúcida não serve de cor de marca).
  def opaque_parts?(parts)
    parts.length == 3 || (parts.length == 4 && %w[1 1.0 100%].include?(parts.last))
  end

  def integer_channel(part)
    return nil if part.empty? || !part.each_char.all? { |char| char.between?('0', '9') }

    value = part.to_i
    value <= 255 ? value : nil
  end

  def hex_digits?(text)
    !text.empty? && text.each_char.all? { |char| HEX_DIGITS.include?(char) }
  end
end
