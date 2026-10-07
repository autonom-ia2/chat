# Turns the content of one column of an imported model into editable blocks (#1099), in reading order. Running text
# (paragraphs, headings, lists, inline formatting) goes to a TextBuffer and comes out grouped by style; images, buttons,
# rules and spacers break the text; a data table becomes lines of text, or a marked placeholder when too complex;
# any other nested table is read through, top to bottom (side-by-side content inside a column stacks). An image inside a
# link that also wraps text (a product card) keeps the link. Every visit checks the import's deadline.
class EmailCampaigns::Import::ContentWalker
  BLOCK = %w[p div h1 h2 h3 h4 h5 h6 ul ol li blockquote pre center table tbody thead tfoot tr td th caption section article header
             footer main aside nav figure figcaption address dl dt dd].freeze
  MIN_SPACER = 4
  SAFE_FONTS = %w[arial helvetica sans-serif].freeze

  def initialize(nodes, report, style: nil, budget: EmailCampaigns::Import::Budget.new)
    @nodes = Array(nodes)
    @report = report
    @budget = budget
    @style = style || EmailCampaigns::Import::TextStyle.inherited_for(@nodes.first)
    @blocks = []
    @links = []
    @buffer = EmailCampaigns::Import::TextBuffer.new
  end

  def call
    @nodes.each { |node| visit(node, @style) }
    flush
    @blocks
  end

  private

  def visit(node, style)
    @budget.time!
    return @buffer.text(node.content, style) if node.text?
    return unless node.element?
    return if special?(node, style)

    BLOCK.include?(node.name) ? block(node, style) : inline(node, style)
  end

  def special?(node, style)
    case node.name
    when 'br' then @buffer.line_break || true
    when 'img', 'hr' then add(media(node, style))
    when 'a' then link?(node, style)
    else (node.name == 'table' && table?(node, style)) || empty?(node)
    end
  end

  def media(node, style)
    node.name == 'img' ? EmailCampaigns::Import::Blocks.image(node, style, href: @links.last) : EmailCampaigns::Import::Blocks.divider(node)
  end

  def link?(node, style)
    if EmailCampaigns::Import::Buttons.image_link?(node)
      add(EmailCampaigns::Import::Blocks.image(node.at_css('img'), style.inherit(node), href: node['href']))
    elsif EmailCampaigns::Import::Buttons.link?(node)
      add(EmailCampaigns::Import::Buttons.build(node, style))
    else
      empty?(node)
    end
  end

  def table?(node, style)
    return add(EmailCampaigns::Import::Buttons.build(node.at_css('a'), style.inherit(node))) if EmailCampaigns::Import::Buttons.table?(node)
    return false unless EmailCampaigns::Import::DataTable.data?(node)
    return add(EmailCampaigns::Import::Blocks.unresolved(node, @report)) if EmailCampaigns::Import::DataTable.complex?(node)

    lines(node, style.inherit(node))
  end

  def lines(node, style)
    @report.add(:table_as_text)
    EmailCampaigns::Import::DataTable.lines(node).each do |line|
      @buffer.paragraph(style, :line)
      @buffer.text(line, style)
    end
    @buffer.paragraph(style)
    true
  end

  # An element without visible text or image: a spacer when it has a height, a rule when it has a border, else nothing.
  def empty?(node)
    return false unless EmailCampaigns::Import::TableParts.visible(node).empty? && node.css('img, hr').empty?

    style = EmailCampaigns::Import::StyleMap.parse(node['style'])
    height = EmailCampaigns::Import::StyleMap.px(style['height'] || node['height'].to_s)
    return add(EmailCampaigns::Import::Blocks.divider(node)) if rule?(style)

    add(EmailCampaigns::Import::Blocks.spacer(height)) if height && height >= MIN_SPACER
    true
  end

  def rule?(style)
    %w[border-top border-bottom].any? { |name| style[name].to_s.downcase.include?('solid') }
  end

  def block(node, style)
    own = style.inherit(node)
    @buffer.paragraph(own, node.name == 'li' ? :item : :para)
    @buffer.text(bullet(node), own) if node.name == 'li'
    node.children.each { |child| visit(child, own) }
    @buffer.paragraph(style)
  end

  def bullet(node)
    return '• ' unless node.parent&.name == 'ol'

    "#{node.parent.element_children.select { |child| child.name == 'li' }.index(node).to_i + 1}. "
  end

  def inline(node, style)
    own = style.inherit(node)
    opening, closing = EmailCampaigns::Import::InlineMarkup.wrap(node, own, style)
    link = node.name == 'a' && node['href'].present?
    @links.push(node['href']) if link
    @buffer.open_inline(opening, closing)
    node.children.each { |child| visit(child, own) }
    @buffer.close_inline
    @links.pop if link
  end

  def add(block)
    flush
    @blocks << block
    true
  end

  def flush
    @buffer.drain.each do |style, html|
      font_replaced(style.font_family)
      @blocks << EmailCampaigns::Import::Blocks.text(style, html)
    end
  end

  # Web and custom fonts give way to Arial, the font every client has.
  def font_replaced(family)
    first = family.to_s.split(',').first.to_s.strip.delete(%q('")).downcase
    @report.add(:font_replaced, item: first) if first.present? && SAFE_FONTS.exclude?(first)
  end
end
