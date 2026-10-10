# The share of the visible area of an imported design that the person can edit (#1099): every block but the parts left
# for later (placeholders of unresolved parts), weighed by an estimate of its rendered area — text by lines at its
# size, images by width and height, buttons by their 44px+ line. The fidelity suite demands at least 70% per model.
module EmailCampaigns::Import::EditableArea
  CHAR_WIDTH = 0.55
  LINE = 1.5
  DEFAULT_FONT = 14.0
  BUTTON_HEIGHT = 48.0
  MIN_UNRESOLVED_HEIGHT = 80.0

  module_function

  def ratio(document)
    areas = areas(document)
    total = areas.sum(&:last)
    return 1.0 if total.zero?

    (areas.reject { |block, _area| block.kind == :unresolved }.sum(&:last) / total).round(3)
  end

  # [block, estimated area] for every block of the design.
  def areas(document)
    document.sections.flat_map do |section|
      widths(section, document.width).flat_map { |column, width| column.blocks.map { |block| [block, area(block, width)] } }
    end
  end

  def widths(section, width)
    section.columns.map do |column|
      share = column.width.to_s.end_with?('%') ? column.width.to_f / 100 : 1.0 / section.columns.size
      [column, (width * share).clamp(1, width)]
    end
  end

  def area(block, width)
    case block.tag
    when 'mj-text' then width * text_height(block.content, block.attrs['font-size'], width)
    when 'mj-image' then image_area(block, width)
    when 'mj-button' then BUTTON_HEIGHT * [width, (characters(block.content) * size(block.attrs['font-size']) * 0.6) + 48].min
    when 'mj-spacer' then width * EmailCampaigns::Import::StyleMap.px(block.attrs['height'].to_s).to_f
    else width * 20
    end
  end

  def image_area(block, width)
    return width * [text_height(block.attrs['alt'], nil, width), MIN_UNRESOLVED_HEIGHT].max if block.kind == :unresolved

    image_width = [EmailCampaigns::Import::StyleMap.px(block.attrs['width'].to_s) || width, width].min
    image_width * image_width * 0.5
  end

  def text_height(content, font_size, width)
    font = size(font_size)
    lines = ((characters(content) * font * CHAR_WIDTH) / width).ceil.clamp(1, 10_000) + (content.to_s.split('<br').size - 1)
    lines * font * LINE
  end

  def characters(content)
    Nokogiri::HTML5.fragment(content.to_s).text.length
  end

  def size(font_size)
    EmailCampaigns::Import::StyleMap.px(font_size.to_s) || DEFAULT_FONT
  end
end
