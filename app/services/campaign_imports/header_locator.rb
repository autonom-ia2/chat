# Finds the header row of a spreadsheet that may start with titles or blank lines (the header
# is not always row 1). Same idea as CampaignImports::SchemaResolver, generalized beyond email:
# a header candidate is a non-blank row with no phone and no email in it, and data rows must
# follow it. The choice is structural (contact data below, known headers, filled cells), it
# never reads the meaning of a header.
#
# With the customer_base reading (#1246, CampaignImports::ContactReading):
# a row that comes after the first data row is data, not a header (a person without phone or
# email, a totals line). A data row has contact data and at least two filled cells, so a title
# such as "Clientes — (11) 98765-4321" in one cell above the header does not count.
#
# A file with no header at all gets untitled columns (header_row 0) and every row as data;
# SpreadsheetReader then asks the user to confirm the columns.
class CampaignImports::HeaderLocator
  Error = Class.new(StandardError)
  HEADER_SCAN_LIMIT = CampaignImports::SchemaResolver::HEADER_SCAN_LIMIT
  UNTITLED_HEADER_ROW = 0
  MIN_DATA_ROW_CELLS = 2
  Candidate = Struct.new(:table, :table_index, :header_index, :headers, :rows, :contact_below, :known_headers, :untitled,
                         keyword_init: true) do
    def header_row_number
      untitled ? UNTITLED_HEADER_ROW : table.rows.fetch(header_index).row_number
    end
  end

  def initialize(parsed, reading: CampaignImports::ContactReading::CLASSIC)
    @parsed = parsed
    @reading = reading
  end

  def perform(header_row: nil, table_index: nil)
    return pinned(header_row, table_index.to_i) if header_row

    candidates = tables.each_with_index.flat_map { |table, index| table_candidates(table, index) }
    best = candidates.max_by { |candidate| score(candidate) }
    best || (untitled_candidate if @reading.customer_base?)
  end

  private

  def pinned(header_row, table_index)
    table = tables[table_index]
    return untitled(table, table_index) if table && header_row == UNTITLED_HEADER_ROW && @reading.customer_base?

    header_index = table&.rows&.index { |row| row.row_number == header_row }
    raise Error, 'header_row_not_found' unless header_index

    build(table, table_index, header_index, contact_below: true)
  end

  def table_candidates(table, table_index)
    contact_rows = table.rows.map { |row| row.values.any? { |value| @reading.contact?(value) } }
    last_contact_row = contact_rows.rindex(true)
    first_data_row = first_data_row(table, contact_rows)
    positions = table.rows.each_index.select { |index| header_position?(table, contact_rows, first_data_row, index) }
    positions.first(HEADER_SCAN_LIMIT).map do |index|
      build(table, table_index, index, contact_below: last_contact_row.present? && last_contact_row > index)
    end
  end

  def build(table, table_index, header_index, contact_below:)
    headers = normalize_headers(table.rows.fetch(header_index).values)
    rows = table.rows.drop(header_index + 1).reject { |row| blank_row?(row) }
    Candidate.new(table: table, table_index: table_index, header_index: header_index, headers: headers, rows: rows,
                  contact_below: contact_below, known_headers: known_header_count(headers), untitled: false)
  end

  # No header row: the table with the most contact rows, read whole.
  def untitled_candidate
    counts = tables.map { |table| table.rows.count { |row| row.values.any? { |value| @reading.contact?(value.to_s) } } }
    best = counts.each_index.max_by { |index| [counts[index], -index] }
    untitled(tables[best], best) if best && counts[best].positive?
  end

  def untitled(table, table_index)
    width = table.rows.map { |row| row.values.size }.max.to_i
    Candidate.new(table: table, table_index: table_index, header_index: -1, headers: Array.new(width, ''),
                  rows: table.rows.reject { |row| blank_row?(row) }, contact_below: true, known_headers: 0, untitled: true)
  end

  def score(candidate)
    [candidate.contact_below ? 1 : 0, candidate.known_headers, candidate.headers.count(&:present?),
     -candidate.table_index, -candidate.header_index]
  end

  def known_header_count(headers)
    CampaignImports::HeaderMapper.new(headers, mode: :phone).perform.mapping.size
  end

  def tables
    return @parsed.tables if @parsed.tables.present?

    header_row = CampaignImports::Parser::ParsedRow.new(row_number: 1, values: @parsed.headers)
    [CampaignImports::Parser::ParsedTable.new(name: nil, delimiter: nil, rows: [header_row, *@parsed.rows])]
  end

  def header_values?(values)
    strings = values.map(&:to_s)
    strings.any? { |value| value.strip.present? } && strings.all? { |value| CampaignImports::ContactValues.readable?(value) }
  end

  # Only the customer_base reading stops looking for the header at the first data row.
  def first_data_row(table, contact_rows)
    return unless @reading.customer_base?

    table.rows.each_index.find { |index| contact_rows[index] && filled_cells(table.rows[index]) >= MIN_DATA_ROW_CELLS }
  end

  # A header holds no contact data and comes before the first data row.
  def header_position?(table, contact_rows, first_data_row, index)
    return false if contact_rows[index] || (first_data_row && index >= first_data_row)

    header_values?(table.rows[index].values)
  end

  def filled_cells(row)
    row.values.count { |value| value.to_s.strip.present? }
  end

  def blank_row?(row)
    row.values.all? { |value| value.to_s.strip.empty? }
  end

  def normalize_headers(values)
    values.map.with_index do |value, index|
      header = value.to_s.strip
      index.zero? ? header.delete_prefix("\uFEFF") : header
    end
  end
end
