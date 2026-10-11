# Cores da imagem de prévia (#1282). A cor da página vem como #RRGGBB; qualquer outra coisa usa a cor padrão da
# página pública. Como o texto sobre ela é branco, a cor é escurecida aos poucos até ter contraste AA (4,5:1) com o
# branco — a mesma regra da página pública (`public_booking_v2/helpers/brand.js`).
module Crm::BookingV2::PreviewImage::Palette
  DEFAULT = '#1d4ed8'.freeze
  HEX_DIGITS = '0123456789abcdef'.freeze
  MIN_CONTRAST = 4.5
  DARKEN_FACTOR = 0.9
  MAX_DARKEN_STEPS = 40
  WHITE = [255, 255, 255].freeze
  INK = [15, 23, 42].freeze
  MUTED = [71, 85, 105].freeze
  PAPER = [248, 250, 252].freeze

  module_function

  def hex?(value)
    text = value.to_s.downcase
    text.length == 7 && text.start_with?('#') && text.delete_prefix('#').each_char.all? { |char| HEX_DIGITS.include?(char) }
  end

  def rgb(value)
    hex = hex?(value) ? value.to_s.downcase : DEFAULT
    [1, 3, 5].map { |start| hex[start, 2].to_i(16) }
  end

  def brand(value)
    color = rgb(value)
    MAX_DARKEN_STEPS.times do
      return color if contrast_with_white(color) >= MIN_CONTRAST

      color = color.map { |channel| (channel * DARKEN_FACTOR).floor }
    end
    rgb(DEFAULT)
  end

  def mix(color, other, amount)
    color.zip(other).map { |from, to| (from + ((to - from) * amount)).round }
  end

  def contrast_with_white(color)
    1.05 / (luminance(color) + 0.05)
  end

  def luminance(color)
    red, green, blue = color.map do |channel|
      value = channel / 255.0
      value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end
end
