# Rows and cells of an HTML table as the browser builds them (#1099): rows directly or through tbody/thead/tfoot,
# cells td and th. Nested tables are never descended into. Also the visible text of a node, with a space where
# cells, paragraphs or line breaks separate its words.
module EmailCampaigns::Import::TableParts
  ROW_GROUPS = %w[tbody thead tfoot].freeze
  CELLS = %w[td th].freeze
  BREAKS = %w[br td th tr p div li h1 h2 h3 h4 h5 h6 table].freeze

  module_function

  def rows(table)
    table.element_children.flat_map do |child|
      next rows(child) if ROW_GROUPS.include?(child.name)

      child.name == 'tr' ? [child] : []
    end
  end

  def cells(row)
    row.element_children.select { |child| CELLS.include?(child.name) }
  end

  def visible(node)
    EmailCampaigns::Import::Visibility.visible_text(node.text)
  end

  # Visible text keeping words apart across cells, paragraphs and line breaks.
  def words(node)
    parts = []
    node.traverse do |child|
      parts << child.content if child.text?
      parts << ' ' if child.element? && BREAKS.include?(child.name)
    end
    EmailCampaigns::Import::Visibility.visible_text(parts.join)
  end
end
