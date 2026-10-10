# Widths of side-by-side cells as MJML column percentages summing to 100 (#1099), from their width attribute or CSS
# width / max-width, all in px or all in %. Nil when any is missing or units are mixed (MJML then splits evenly).
module EmailCampaigns::Import::ColumnWidths
  module_function

  def percentages(cells)
    values = cells.map { |cell| width(cell) }
    return unless values.all? && values.map(&:last).uniq.one?

    shares(values.map(&:first))
  end

  def shares(numbers)
    total = numbers.sum
    return if total <= 0

    shares = numbers[0...-1].map { |number| (number * 100.0 / total).round(2) }
    (shares + [(100 - shares.sum).round(2)]).map { |share| format_share(share) }
  end

  # [number, :px | :percent] or nil.
  def width(cell)
    style = EmailCampaigns::Import::StyleMap.parse(cell['style'])
    [cell['width'], style['width'], style['max-width']].each do |value|
      text = EmailCampaigns::Import::StyleMap.plain(value)
      next if text.empty?
      return [text.delete_suffix('%').to_f, :percent] if text.end_with?('%') && text.to_f.positive?

      px = EmailCampaigns::Import::StyleMap.px(text)
      return [px, :px] if px&.positive?
    end
    nil
  end

  def format_share(share)
    share == share.round ? "#{share.round}%" : "#{share}%"
  end
end
