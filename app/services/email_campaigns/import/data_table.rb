# A table of data (prices, schedules, invoice lines) rather than of layout (#1099): two rows or more, every filled row
# with the same number (two or more) of filled cells, short text only — no image, link or nested table. A simple one becomes lines of text
# ("Serviço 1 — R$ 19,99"); one with merged cells or more than four columns is left for later as a marked image.
module EmailCampaigns::Import::DataTable
  MAX_CELL_CHARS = 120
  MAX_COLUMNS = 4
  SEPARATOR = ' — '.freeze

  module_function

  def data?(table)
    rows = EmailCampaigns::Import::TableParts.rows(table)
    return false if rows.size < 2 || table.css('img, table, a[href]').any?

    cells = rows.map { |row| filled(row) }.reject(&:empty?)
    uniform?(cells) && cells.flatten.all? { |cell| EmailCampaigns::Import::TableParts.words(cell).length <= MAX_CELL_CHARS }
  end

  # Every filled row has the same number of filled cells, two or more.
  def uniform?(cells)
    counts = cells.map(&:size).uniq
    counts.one? && counts.first >= 2
  end

  def complex?(table)
    rows = EmailCampaigns::Import::TableParts.rows(table)
    cells = rows.flat_map { |row| EmailCampaigns::Import::TableParts.cells(row) }
    merged = cells.any? { |cell| cell['colspan'].to_i > 1 || cell['rowspan'].to_i > 1 }
    merged || rows.map { |row| filled(row).size }.max.to_i > MAX_COLUMNS
  end

  def lines(table)
    EmailCampaigns::Import::TableParts.rows(table).filter_map do |row|
      line = filled(row).map { |cell| EmailCampaigns::Import::TableParts.words(cell) }.join(SEPARATOR)
      line.presence
    end
  end

  def filled(row)
    EmailCampaigns::Import::TableParts.cells(row).reject { |cell| EmailCampaigns::Import::TableParts.visible(cell).empty? }
  end
end
