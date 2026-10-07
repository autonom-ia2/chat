# Buttons of an imported model (#1099): a link with a background color of its own, or the only content of a cell (or
# of a small table) that has one. Becomes an mj-button with the colors, size, corners and inner padding it had.
module EmailCampaigns::Import::Buttons
  CELL_LEVELS = 4
  DEFAULT_INNER_PADDING = '12px 24px 12px 24px'.freeze
  PADDING = '8px 0px 16px 0px'.freeze
  LINE_INNER_PADDING = '0px 24px 0px 24px'.freeze
  ALIGNS = %w[left center right].freeze

  module_function

  def image_link?(link)
    link.css('img').one? && EmailCampaigns::Import::TableParts.visible(link).empty?
  end

  def link?(link)
    link['href'].present? && link.css('img').empty? && EmailCampaigns::Import::TableParts.visible(link).present? &&
      background(link).present?
  end

  def table?(table)
    links = table.css('a')
    links.one? && table.css('img').empty? && same_text?(table, links.first) && link?(links.first)
  end

  def background(link)
    own_background(link) || ((holder = cell(link)) && own_background(holder))
  end

  def own_background(node)
    EmailCampaigns::Import::StyleMap.color(style(node)['background-color']) || EmailCampaigns::Import::StyleMap.color(node['bgcolor'])
  end

  def cell(link)
    link.ancestors.first(CELL_LEVELS).find do |ancestor|
      EmailCampaigns::Import::TableParts::CELLS.include?(ancestor.name) && same_text?(ancestor, link) &&
        ancestor.css('a').one? && ancestor.css('img').empty?
    end
  end

  def same_text?(first, second)
    EmailCampaigns::Import::TableParts.visible(first) == EmailCampaigns::Import::TableParts.visible(second)
  end

  def style(node)
    EmailCampaigns::Import::StyleMap.parse(node['style'])
  end

  def build(link, inherited)
    own = style(link)
    holder = cell(link)
    outer = holder ? style(holder) : {}
    text = inherited.inherit(link)
    attrs = { 'href' => link['href'], 'background-color' => background(link), 'color' => color(own, outer),
              'font-family' => EmailCampaigns::Import::WebFonts.stack(text.font_family), 'font-size' => "#{text.font_size.round}px",
              'font-weight' => text.bold ? '700' : nil, 'border-radius' => radius(own, outer), 'inner-padding' => inner_padding(own, outer),
              'line-height' => line_height(own), 'width' => width(own), 'align' => align(link, holder, text), 'padding' => PADDING }
    EmailCampaigns::Import::Model::Block.new(tag: 'mj-button', attrs: attrs, content: escape(EmailCampaigns::Import::TableParts.visible(link)))
  end

  def color(own, outer)
    EmailCampaigns::Import::StyleMap.color(own['color']) || EmailCampaigns::Import::StyleMap.color(outer['color']) || '#ffffff'
  end

  def radius(own, outer)
    value = EmailCampaigns::Import::StyleMap.plain(own['border-radius'] || outer['border-radius'])
    px = EmailCampaigns::Import::StyleMap.px(value.split.first.to_s)
    "#{px.round}px" if px
  end

  # A button sized by its line height (a tall line, no padding) keeps that height: no vertical padding is added.
  def inner_padding(own, outer)
    EmailCampaigns::Import::StyleMap.padding(own['padding'].to_s) || EmailCampaigns::Import::StyleMap.padding(outer['padding'].to_s) ||
      (line_height(own) ? LINE_INNER_PADDING : DEFAULT_INNER_PADDING)
  end

  def line_height(own)
    value = EmailCampaigns::Import::StyleMap.plain(own['line-height'])
    px = EmailCampaigns::Import::StyleMap.px(value)
    "#{px.round}px" if px && value.end_with?('px')
  end

  def width(own)
    value = EmailCampaigns::Import::StyleMap.plain(own['width'])
    px = EmailCampaigns::Import::StyleMap.px(value)
    "#{px.round}px" if px && px > 40 && !value.end_with?('%')
  end

  def align(link, holder, text)
    table = link.ancestors.first(CELL_LEVELS + 2).find { |ancestor| ancestor.name == 'table' && ancestor['align'].present? }
    candidates = [holder, table].compact.pluck('align') + [text.align]
    candidates.map { |value| value.to_s.downcase }.find { |value| ALIGNS.include?(value) } || 'center'
  end

  def escape(text)
    text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
