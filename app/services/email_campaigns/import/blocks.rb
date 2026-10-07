# Builders of the editable blocks of an imported model (#1099): mj-text from grouped paragraphs (in the original font
# when every e-mail shows it, WebFonts), mj-image (with a
# placeholder where the image could not be used), mj-divider, mj-spacer, and the marked placeholder image of a part
# left for later (registered in the report with its text and markup, for the AI to rebuild on request).
module EmailCampaigns::Import::Blocks
  PADDING = '0px 0px 12px 0px'.freeze
  IMAGE_ALIGNS = %w[left center right].freeze
  MAX_ALT = 250
  MAX_SPACER = 120
  DEFAULT_RULE = '#cccccc'.freeze

  module_function

  def text(style, html)
    attrs = { 'font-family' => EmailCampaigns::Import::WebFonts.stack(style.font_family), 'font-size' => "#{style.font_size.round}px",
              'color' => style.color, 'font-weight' => style.bold ? '700' : nil, 'font-style' => style.italic ? 'italic' : nil,
              'line-height' => style.line_height, 'align' => style.align, 'padding' => PADDING }
    EmailCampaigns::Import::Model::Block.new(tag: 'mj-text', attrs: attrs, content: html)
  end

  def image(node, style, href: nil)
    missing = node['data-import-missing'].present?
    attrs = { 'src' => missing ? EmailCampaigns::Import::Placeholders::MISSING_SRC : node['src'], 'alt' => node['alt'].to_s.strip,
              'href' => href, 'width' => width(node), 'align' => image_align(node, style), 'padding' => PADDING,
              'css-class' => missing ? EmailCampaigns::Import::Placeholders::MISSING_CLASS : nil }
    EmailCampaigns::Import::Model::Block.new(tag: 'mj-image', attrs: attrs, kind: missing ? :missing : :editable)
  end

  def width(node)
    style = EmailCampaigns::Import::StyleMap.parse(node['style'])
    [node['width'], style['width'], style['max-width']].each do |value|
      text = EmailCampaigns::Import::StyleMap.plain(value)
      next if text.empty? || text.end_with?('%')

      px = EmailCampaigns::Import::StyleMap.px(text)
      return "#{px.round}px" if px && px >= 2
    end
    nil
  end

  def image_align(node, style)
    value = node['align'].to_s.downcase
    value = style.align.to_s unless IMAGE_ALIGNS.include?(value)
    IMAGE_ALIGNS.include?(value) ? value : 'center'
  end

  def divider(node)
    style = EmailCampaigns::Import::StyleMap.parse(node['style'])
    border = style.values_at('border-top', 'border-bottom', 'border').compact.first.to_s
    width = border.split.filter_map { |part| EmailCampaigns::Import::StyleMap.px(part) }.first || 1
    attrs = { 'border-color' => rule_color(border, style, node), 'border-width' => "#{width.round.clamp(1, 8)}px",
              'padding' => '8px 0px 8px 0px' }
    EmailCampaigns::Import::Model::Block.new(tag: 'mj-divider', attrs: attrs)
  end

  def rule_color(border, style, node)
    [EmailCampaigns::Import::StyleMap.first_color(border), EmailCampaigns::Import::StyleMap.color(style['border-color']),
     EmailCampaigns::Import::StyleMap.color(node['color'])].compact.first || DEFAULT_RULE
  end

  def spacer(height)
    EmailCampaigns::Import::Model::Block.new(tag: 'mj-spacer', attrs: { 'height' => "#{height.round.clamp(4, MAX_SPACER)}px" })
  end

  def unresolved(node, report)
    text = EmailCampaigns::Import::TableParts.words(node)
    id = report.add_unresolved(text: text, html: node.to_html)
    node.css('a[href]').each { |link| report.drop_link(link['href'], :unresolved) }
    node.css('img[src]').each { |image| report.drop_image(image['src'], :unresolved) }
    attrs = { 'src' => EmailCampaigns::Import::Placeholders::UNRESOLVED_SRC, 'alt' => text[0, MAX_ALT], 'title' => id,
              'css-class' => EmailCampaigns::Import::Placeholders::UNRESOLVED_CLASS, 'padding' => PADDING }
    EmailCampaigns::Import::Model::Block.new(tag: 'mj-image', attrs: attrs, kind: :unresolved)
  end
end
