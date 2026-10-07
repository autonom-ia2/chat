# Converts the cleaned body of an imported HTML model into the importer's design (#1099). The container 300–800px wide
# becomes the body (its outer background, the body's); each row becomes a section and each cell side by side a column
# (widths kept as percentages; columns stack on the phone, as MJML columns do); a cell's background color, background
# image and padding go to its section; its content goes through ContentWalker. A row that is pure content is a section of
# its own; inline content between rows is grouped into one.
class EmailCampaigns::Import::Converter
  Box = Struct.new(:background, :background_url, :padding)
  DEFAULT_WIDTH = 600
  WIDTH_RANGE = (300..800)
  HERO_MIN_HEIGHT = 100
  SECTION_PADDING = '10px 24px 10px 24px'.freeze
  ROW_TAGS = %w[tr table].freeze
  BOX_TAGS = %w[div center section article header footer main aside td th].freeze

  def self.call(body, report, budget: EmailCampaigns::Import::Budget.new)
    new(body, report, budget).call
  end

  def initialize(body, report, budget)
    @body = body
    @report = report
    @budget = budget
    @layout = EmailCampaigns::Import::Layout.new
  end

  def call
    container, width, outer, inner = find_container
    sections = sections_for(container, Box.new(inner, nil, nil))
    EmailCampaigns::Import::Model::Document.new(width: width, background: outer, sections: sections)
  end

  private

  # Walks down single-child wrappers to the box 300–800px wide; its outer backgrounds are the body's.
  def find_container
    node = @body
    outer = nil
    loop do
      width = box_width(node)
      return [node, width.round, outer, background(node)] if width && WIDTH_RANGE.cover?(width)

      outer = background(node) || outer
      child = only_child(node)
      return [node, DEFAULT_WIDTH, outer, nil] unless child

      node = child
    end
  end

  def only_child(node)
    return if node.children.any? { |child| child.text? && @layout.content?(child) }

    children = node.element_children.select { |child| @layout.content?(child) }
    children.first if children.one?
  end

  def sections_for(node, box)
    @budget.time!
    box = box_for(node, box)
    return [] unless @layout.content?(node)

    columns = @layout.columns(node)
    return [multi_section(columns, box)].compact if columns
    return [leaf_section([node], box)].compact unless @layout.structural?(node) || layout_table?(node)

    padded(children_sections(node, box), box)
  end

  def children_sections(node, box)
    sections = []
    run = []
    children = node.name == 'table' ? EmailCampaigns::Import::TableParts.rows(node) : node.children.to_a
    children.each do |child|
      next run << child unless section_child?(child)

      sections << leaf_section(run, box) if run.any?
      run = []
      sections.concat(sections_for(child, without_padding(box)))
    end
    sections << leaf_section(run, box) if run.any?
    sections.compact
  end

  # The padding of a wrapper reaches the one section it produced.
  def padded(sections, box)
    return sections unless box.padding && sections.one? && sections.first.padding == SECTION_PADDING

    [sections.first.with(padding: box.padding)]
  end

  def section_child?(child)
    child.element? && (@layout.structural?(child) || row?(child))
  end

  def without_padding(box)
    Box.new(box.background, box.background_url, nil)
  end

  def layout_table?(node)
    node.name == 'table' && @layout.layout_table?(node)
  end

  def row?(node)
    return true if ROW_TAGS.include?(node.name)

    BOX_TAGS.include?(node.name) && (background(node) || node['data-import-bg'] || padding(node)).present?
  end

  def box_for(node, box)
    Box.new(*own_box(node, single_cell(node) || node).zip(box.to_a).map { |mine, outer| mine || outer })
  end

  # [background, background image, padding] set on the node itself (or on the only cell of its row).
  def own_box(node, holder)
    pair = [node, holder]
    [pair.filter_map { |item| background(item) }.first, pair.filter_map { |item| item['data-import-bg'] }.first,
     pair.reverse.filter_map { |item| padding(item) }.first || hero_padding(holder)]
  end

  # A background-image cell sized by its height (text over it, no padding) keeps about that height.
  def hero_padding(holder)
    height = EmailCampaigns::Import::StyleMap.px(holder['height'].to_s)
    return unless holder['data-import-bg'] && height && height >= HERO_MIN_HEIGHT

    vertical = (height / 3).round
    "#{vertical}px 24px #{vertical}px 24px"
  end

  def single_cell(node)
    return unless node.element? && node.name == 'tr'

    cells = EmailCampaigns::Import::TableParts.cells(node).select { |cell| @layout.content?(cell) }
    cells.first if cells.one?
  end

  def leaf_section(nodes, box)
    return if nodes.none? { |node| node.element? || @layout.content?(node) }

    blocks = EmailCampaigns::Import::ContentWalker.new(nodes, @report, budget: @budget).call
    return if blocks.empty?

    EmailCampaigns::Import::Model::Section.new(columns: [EmailCampaigns::Import::Model::Column.new(blocks: blocks)],
                                               background: box.background, background_url: box.background_url,
                                               padding: box.padding || SECTION_PADDING)
  end

  def multi_section(cells, box)
    columns = cells.filter_map { |cell| column(cell, box) }
    return if columns.empty?

    widths = EmailCampaigns::Import::ColumnWidths.percentages(cells) if columns.size == cells.size
    columns = columns.each_with_index.map { |column, index| column.with(width: widths&.[](index)) }
    EmailCampaigns::Import::Model::Section.new(columns: columns, background: box.background, background_url: box.background_url,
                                               padding: box.padding || SECTION_PADDING)
  end

  def column(cell, box)
    blocks = EmailCampaigns::Import::ContentWalker.new([cell], @report, budget: @budget).call
    return if blocks.empty?

    @report.add(:layout_stacked) if cell.css('*').any? { |node| @layout.columns(node) }
    own = background(cell)
    EmailCampaigns::Import::Model::Column.new(blocks: blocks, padding: padding(cell), background: own == box.background ? nil : own)
  end

  def background(node)
    return unless node.element?

    EmailCampaigns::Import::StyleMap.color(style(node)['background-color']) || EmailCampaigns::Import::StyleMap.color(node['bgcolor'])
  end

  def padding(node)
    return unless node.element?

    EmailCampaigns::Import::StyleMap.padding_of(style(node))
  end

  def box_width(node)
    candidates = [node['width'], style(node)['width'], style(node)['max-width']]
    candidates.each do |value|
      text = EmailCampaigns::Import::StyleMap.plain(value)
      next if text.empty? || text.end_with?('%')

      px = EmailCampaigns::Import::StyleMap.px(text)
      return px if px
    end
    nil
  end

  def style(node)
    EmailCampaigns::Import::StyleMap.parse(node['style'])
  end
end
