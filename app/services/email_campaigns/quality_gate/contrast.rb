# WCAG 2.x contrast ratio between two hex colors (#rgb or #rrggbb). Plain string parsing, no regex.
module EmailCampaigns::QualityGate::Contrast
  STEPS = 20
  DARK_LUMINANCE = 0.179
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

  # The color closest to `color` that reaches `needed` against `background` (#1099): mixed step by step toward black on a
  # light background or toward white on a dark one. Unreadable colors start from black. Returns #rrggbb.
  def adjust(color, background, needed)
    start = rgb(color) || [0, 0, 0]
    target = luminance(background).to_f > DARK_LUMINANCE ? [0, 0, 0] : [255, 255, 255]
    (0..STEPS).each do |step|
      mixed = hex(start.zip(target).map { |from, to| (from + ((to - from) * step / STEPS.to_f)).round })
      return mixed if ratio(mixed, background).to_f >= needed
    end
    hex(target)
  end

  def hex(channels)
    "##{channels.map { |channel| channel.to_s(16).rjust(2, '0') }.join}"
  end

  def linear(channel)
    channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
  end
end
