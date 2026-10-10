# Reads the layout of an imported model (#1099): whether a node has visible content, which of its children sit side
# by side (cells of a row, inline-block or floated boxes, aligned tables, children of a flex or grid box), and whether
# it holds layout at all or is plain content. Answers are memoized per node.
class EmailCampaigns::Import::Layout
  SIDE_DISPLAYS = %w[inline-block table-cell inline-table inline-flex].freeze
  ROW_DISPLAYS = %w[flex grid inline-flex inline-grid].freeze
  FLOATS = %w[left right].freeze

  def initialize
    @content = {}
    @structural = {}
  end

  def content?(node)
    @content.fetch(node) do
      @content[node] = if node.text?
                         EmailCampaigns::Import::Visibility.visible_text(node.content).present?
                       else
                         node.element? && element_content?(node)
                       end
    end
  end

  # Children laid out side by side, or nil.
  def columns(node)
    return unless node.element?

    candidates = node.name == 'tr' ? EmailCampaigns::Import::TableParts.cells(node) : node.element_children
    filled = candidates.select { |child| content?(child) }
    return if filled.size < 2

    filled if node.name == 'tr' || side_by_side?(node, filled)
  end

  def structural?(node)
    return false unless node.element? && (node.name != 'table' || layout_table?(node))

    @structural.fetch(node) do
      @structural[node] = columns(node).present? || node.element_children.any? { |child| layout_child?(child) }
    end
  end

  # A table that lays content out, as opposed to a button or a table of data, which are content.
  def layout_table?(table)
    @layout_tables ||= {}
    @layout_tables.fetch(table) do
      @layout_tables[table] = !EmailCampaigns::Import::Buttons.table?(table) && !EmailCampaigns::Import::DataTable.data?(table)
    end
  end

  private

  def element_content?(node)
    %w[img hr].include?(node.name) || EmailCampaigns::Import::TableParts.visible(node).present? || node.at_css('img, hr').present?
  end

  def layout_child?(child)
    child.name == 'table' ? layout_table?(child) : structural?(child)
  end

  def side_by_side?(parent, children)
    return true if ROW_DISPLAYS.include?(display(parent))

    children.all? { |child| beside?(child) }
  end

  def beside?(child)
    style = EmailCampaigns::Import::StyleMap.parse(child['style'])
    SIDE_DISPLAYS.include?(display(child)) || FLOATS.include?(EmailCampaigns::Import::StyleMap.plain(style['float']).downcase) ||
      (child.name == 'table' && FLOATS.include?(child['align'].to_s.downcase))
  end

  def display(node)
    EmailCampaigns::Import::StyleMap.plain(EmailCampaigns::Import::StyleMap.parse(node['style'])['display']).downcase
  end
end
