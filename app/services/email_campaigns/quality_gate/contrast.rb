# WCAG 2.x contrast ratio between two hex colors (#rgb or #rrggbb). Plain string parsing, no regex.
module EmailCampaigns::QualityGate::Contrast
  HEX = '0123456789abcdef'.freeze

  module_function

  # nil when either color is not a hex color the gate can measure.
  def ratio(foreground, background)
    first = luminance(foreground)
    second = luminance(background)
    return if first.nil? || second.nil?

    lighter, darker = [first, second].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  def luminance(color)
    channels = rgb(color)
    return if channels.nil?

    red, green, blue = channels.map { |channel| linear(channel / 255.0) }
    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end

  def rgb(color)
    digits = color.to_s.strip.downcase.delete_prefix('#')
    digits = digits.chars.map { |char| char * 2 }.join if digits.length == 3
    return unless digits.length == 6 && digits.each_char.all? { |char| HEX.include?(char) }

    [0, 2, 4].map { |index| digits[index, 2].to_i(16) }
  end

  def linear(channel)
    channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
  end
end
