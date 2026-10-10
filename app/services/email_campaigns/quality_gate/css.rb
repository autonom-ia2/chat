# CSS value helpers for the quality gate: px lengths, line heights and inline style declarations. No regex.
module EmailCampaigns::QualityGate::Css
  private

  def px(value)
    value.to_s.strip.delete_suffix('px').to_f
  end

  # line-height as px, % of the font size, or a unitless multiplier.
  def line_px(value, font_size)
    return px(value) if value.end_with?('px')
    return font_size * value.delete_suffix('%').to_f / 100 if value.end_with?('%')

    font_size * value.to_f
  end

  def style(node)
    node['style'].to_s.split(';').each_with_object({}) do |declaration, out|
      key, value = declaration.split(':', 2)
      out[key.strip.downcase] = value.strip if value
    end
  end
end
