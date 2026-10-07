# The MJML path of a template import (#1099): models some editors export as MJML (often pasted as "the HTML"). The
# source is canonicalized (head defaults and mj-class written on each element) — MJML that does not parse is refused,
# never kept as written. Sections, columns and editable blocks are read into the importer's design with allowlisted
# attributes; the HTML inside text blocks goes through the same Cleaner as an HTML import. Blocks the editor cannot
# edit become editable ones: mj-hero a section with a background image, mj-navbar a line of links, mj-table lines of
# text, mj-accordion text, mj-carousel images; mj-raw (and a table too complex) a marked placeholder for later.
class EmailCampaigns::Import::MjmlSource
  ALLOWED = JSON.parse(Rails.root.join('app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/' \
                                       'mjmlAllowedAttributes.json').read).fetch('components').freeze
  URL_ATTRIBUTES = %w[href src background-url].freeze
  NAVBAR_JOIN = ' · '.freeze

  def self.call(source, report, base_url: nil)
    new(source, report, base_url).call
  end

  def initialize(source, report, base_url)
    @source = source
    @report = report
    @base_url = base_url
    @links = EmailCampaigns::Import::LinkPolicy.new(report, base_url: base_url)
    @tags = EmailCampaigns::Import::MergeTags.new(report)
  end

  def call
    document = nil
    EmailCampaigns::MjmlCanonicalizer.call(canonical) do |root, cut|
      document = build(root, cut)
      {}
    end
    document
  end

  private

  def canonical
    parsed = false
    out = EmailCampaigns::MjmlCanonicalizer.call(@source) do |root, _cut|
      EmailCampaigns::Import::Limits.check_tree!(root)
      parsed = true
      {}
    end
    raise EmailCampaigns::Import::Error, :malformed_mjml unless parsed

    out
  end

  def build(root, cut)
    @cut = cut
    @slots = cut.slots.each_index.index_by { |index| cut.token(index) }
    mjml = root.at_xpath('./mjml') || root
    body = mjml.at_xpath('./mj-body')
    raise EmailCampaigns::Import::Error, :empty if body.nil?

    title, preview = head(mjml.at_xpath('./mj-head'))
    @report.add(:include_ignored) if mjml.xpath('.//mj-include').any?
    sections = body.element_children.flat_map { |child| body_child(child) }
    EmailCampaigns::Import::Model::Document.new(title: title, preview: preview, sections: sections, background: color(body['background-color']),
                                                width: (EmailCampaigns::Import::StyleMap.px(body['width'].to_s) || 600).round)
  end

  def head(node)
    return [nil, nil] if node.nil?

    @report.add(:web_font_ignored) if node.xpath('./mj-font').any?
    @report.add(:styles_dropped) if node.xpath('./mj-style').any?
    title = node.at_xpath('./mj-title')
    preview = node.at_xpath('./mj-preview')
    [title && plain(title), preview && plain(preview)].map(&:presence)
  end

  def plain(node)
    @tags.plain_text(EmailCampaigns::Import::Visibility.visible_text(Nokogiri::HTML5.fragment(content(node)).text))
  end

  def body_child(node)
    case node.name
    when 'mj-section' then section(node, nil)
    when 'mj-wrapper' then node.element_children.flat_map { |child| child.name == 'mj-section' ? section(child, node) : body_child(child) }
    when 'mj-hero' then hero(node)
    when 'mj-include' then []
    else single(blocks_for(node))
    end
  end

  def section(node, wrapper)
    columns = section_columns(node)
    return [] if columns.empty?

    background = color(node['background-color'] || wrapper&.[]('background-color'))
    [EmailCampaigns::Import::Model::Section.new(columns: columns, background: background, background_url: background_url(node['background-url']),
                                                padding: EmailCampaigns::Import::StyleMap.padding(node['padding'].to_s))]
  end

  def section_columns(node)
    children = node.element_children.flat_map { |child| child.name == 'mj-group' ? child.element_children : [child] }
    children.filter_map { |child| child.name == 'mj-column' ? column(child) : loose(child) }
  end

  def hero(node)
    @report.add(:hero_converted)
    blocks = node.element_children.flat_map { |child| blocks_for(child) }
    return [] if blocks.empty?

    [EmailCampaigns::Import::Model::Section.new(columns: [EmailCampaigns::Import::Model::Column.new(blocks: blocks)],
                                                background: color(node['background-color']),
                                                background_url: background_url(node['background-url']),
                                                padding: EmailCampaigns::Import::StyleMap.padding(node['padding'].to_s))]
  end

  def single(blocks)
    return [] if blocks.empty?

    [EmailCampaigns::Import::Model::Section.new(columns: [EmailCampaigns::Import::Model::Column.new(blocks: blocks)])]
  end

  def column(node)
    blocks = node.element_children.flat_map { |child| blocks_for(child) }
    return if blocks.empty?

    width = node['width'].to_s.strip
    EmailCampaigns::Import::Model::Column.new(blocks: blocks, width: width.end_with?('%', 'px') ? width : nil,
                                              padding: EmailCampaigns::Import::StyleMap.padding(node['padding'].to_s),
                                              background: color(node['background-color']))
  end

  def loose(node)
    blocks = blocks_for(node)
    EmailCampaigns::Import::Model::Column.new(blocks: blocks) if blocks.any?
  end

  def blocks_for(node)
    EmailCampaigns::Import::MjmlBlocks.new(self, @report).call(node)
  end

  public

  attr_reader :links, :tags

  # The raw ending-tag content of an MJML element (HTML for MJML), as written.
  def content(node)
    index = @slots[node.text]
    index ? @cut.slots[index].content : ''
  end

  # A cleaned HTML fragment of an ending tag's content.
  def fragment(html)
    root = Nokogiri::HTML5.fragment(html.to_s)
    EmailCampaigns::Import::Cleaner.call(root, @report, base_url: @base_url)
  end

  def allowed(node)
    names = ALLOWED.fetch(node.name, []) - URL_ATTRIBUTES
    node.attribute_nodes.each_with_object({}) do |attribute, out|
      next unless names.include?(attribute.name)
      next @report.add(:unsafe_css_removed) if unsafe?(attribute.value)

      out[attribute.name] = attribute.value
    end
  end

  def href(value)
    return if value.blank?

    rewritten = @tags.attribute(value, link: true)
    return @report.drop_link(value, :platform_link) && nil if rewritten == :platform_link

    @links.href(rewritten)
  end

  def color(value)
    EmailCampaigns::Import::StyleMap.color(value.to_s) || value.presence
  end

  private

  def background_url(value)
    return if value.blank?

    src, kind = @links.image(@tags.attribute(value, link: false))
    src unless kind == :missing
  end

  def unsafe?(value)
    lower = EmailCampaigns::Import::Url.compact(value).downcase
    EmailCampaigns::Import::Sanitizer::UNSAFE_VALUES.any? { |marker| lower.include?(marker) }
  end
end
