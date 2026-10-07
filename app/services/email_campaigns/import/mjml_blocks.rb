# Reads one MJML element of an imported model into editable blocks (#1099), for MjmlSource: text through the HTML
# Cleaner and ContentWalker (so <p>, <h1> or lists inside an mj-text come out as the inline markup the editor keeps),
# buttons, images, rules, spacers and social links with allowlisted attributes, and the blocks the editor cannot edit
# turned into ones it can (navbar, table, accordion, carousel) or, for raw HTML, a marked placeholder.
class EmailCampaigns::Import::MjmlBlocks
  BOLD = %w[bold 600 700 800 900].freeze
  MJML_FONT_PX = 13.0

  def initialize(source, report)
    @source = source
    @report = report
  end

  # Readers returning a list of blocks, and readers returning one block or nil.
  MANY = { 'mj-text' => :text, 'mj-table' => :table, 'mj-accordion' => :accordion, 'mj-carousel' => :carousel }.freeze
  ONE = { 'mj-button' => :button, 'mj-image' => :image, 'mj-divider' => :plain, 'mj-spacer' => :plain, 'mj-social' => :social,
          'mj-navbar' => :navbar, 'mj-raw' => :raw_block }.freeze

  def call(node)
    return send(MANY[node.name], node) if MANY.key?(node.name)

    [ONE[node.name] && send(ONE[node.name], node)].compact
  end

  private

  def style(node)
    EmailCampaigns::Import::TextStyle.default.with(
      font_size: EmailCampaigns::Import::StyleMap.px(node['font-size'].to_s) || MJML_FONT_PX, color: @source.color(node['color']) || '#000000',
      font_family: node['font-family'], bold: BOLD.include?(node['font-weight'].to_s), italic: node['font-style'] == 'italic',
      line_height: node['line-height'].presence, align: node['align'].presence || 'left'
    )
  end

  def text(node)
    fragment = @source.fragment(@source.content(node))
    blocks = EmailCampaigns::Import::ContentWalker.new(fragment.children.to_a, @report, style: style(node)).call
    padding = EmailCampaigns::Import::StyleMap.padding(node['padding'].to_s)
    return blocks unless padding && blocks.one? && blocks.first.tag == 'mj-text'

    [blocks.first.with(attrs: blocks.first.attrs.merge('padding' => padding))]
  end

  def label(node)
    EmailCampaigns::Import::Visibility.visible_text(@source.fragment(@source.content(node)).text)
  end

  def button(node)
    text = label(node)
    return if text.empty?

    attrs = @source.allowed(node).merge('href' => @source.href(node['href']))
    EmailCampaigns::Import::Model::Block.new(tag: 'mj-button', attrs: attrs, content: escape(text))
  end

  def image(node)
    src, kind = @source.links.image(@source.tags.attribute(node['src'].to_s, link: false))
    missing = kind == :missing
    attrs = @source.allowed(node).merge(
      'src' => missing ? EmailCampaigns::Import::Placeholders::MISSING_SRC : src, 'href' => @source.href(node['href']),
      'alt' => @source.tags.attribute(node['alt'].to_s, link: false).to_s,
      'css-class' => missing ? EmailCampaigns::Import::Placeholders::MISSING_CLASS : nil
    )
    EmailCampaigns::Import::Model::Block.new(tag: 'mj-image', attrs: attrs, kind: missing ? :missing : :editable)
  end

  def social(node)
    elements = node.xpath('./mj-social-element').filter_map do |element|
      attrs = @source.allowed(element).merge('href' => @source.href(element['href']))
      icon, kind = element['src'].present? ? @source.links.image(element['src']) : [nil, nil]
      attrs['src'] = icon if kind && kind != :missing
      "<mj-social-element#{attributes(attrs)}>#{escape(label(element))}</mj-social-element>"
    end
    return if elements.empty?

    EmailCampaigns::Import::Model::Block.new(tag: 'mj-social', attrs: @source.allowed(node), content: elements.join)
  end

  def table(node)
    table = @source.fragment("<table>#{@source.content(node)}</table>").at_css('table')
    return [] if table.nil?

    EmailCampaigns::Import::ContentWalker.new([table], @report, style: style(node)).call
  end

  def accordion(node)
    @report.add(:accordion_converted)
    node.xpath('.//mj-accordion-element').filter_map do |element|
      title = element.at_xpath('./mj-accordion-title')
      body = element.at_xpath('./mj-accordion-text')
      parts = [title && "<strong>#{escape(label(title))}</strong>", body && escape(label(body))].compact_blank
      EmailCampaigns::Import::Blocks.text(style(node), parts.join('<br/>')) if parts.any?
    end
  end

  def carousel(node)
    @report.add(:carousel_converted)
    node.xpath('.//mj-carousel-image').map { |image| image(image) }
  end

  def navbar(node)
    links = EmailCampaigns::Import::LinkPolicy.new(@report, base_url: node['base-url'].presence || nil)
    items = node.xpath('./mj-navbar-link').filter_map { |link| navbar_link(link, links) }
    return if items.empty?

    @report.add(:navbar_converted)
    first = node.at_xpath('./mj-navbar-link')
    EmailCampaigns::Import::Blocks.text(style(first).with(align: node['align'].presence || 'center'),
                                        items.join(EmailCampaigns::Import::MjmlSource::NAVBAR_JOIN))
  end

  def navbar_link(link, links)
    text = label(link)
    return if text.empty?

    href = links.href(@source.tags.attribute(link['href'].to_s, link: true).to_s)
    color = @source.color(link['color']) || '#000000'
    href ? %(<a href="#{escape_attribute(href)}" style="color:#{color};text-decoration:none">#{escape(text)}</a>) : escape(text)
  end

  def plain(node)
    EmailCampaigns::Import::Model::Block.new(tag: node.name, attrs: @source.allowed(node))
  end

  def raw_block(node)
    fragment = @source.fragment(@source.content(node))
    return if EmailCampaigns::Import::TableParts.visible(fragment).empty? && fragment.css('img').empty?

    EmailCampaigns::Import::Blocks.unresolved(fragment, @report)
  end

  def attributes(hash)
    hash.compact.map { |name, value| %( #{name}="#{escape_attribute(value.to_s)}") }.join
  end

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def escape_attribute(value)
    value.to_s.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;')
  end
end
