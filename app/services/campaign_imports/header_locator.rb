# Finds the header row of a spreadsheet that may start with titles or blank lines (the header
# is not always row 1). Same idea as CampaignImports::SchemaResolver, generalized beyond email:
# a header candidate is a non-blank row with no phone and no email in it, and data rows must
# follow it. The choice is structural (contact data below, known headers, filled cells), it
# never reads the meaning of a header.
class CampaignImports::HeaderLocator
  Error = Class.new(StandardError)
  HEADER_SCAN_LIMIT = CampaignImports::SchemaResolver::HEADER_SCAN_LIMIT
  Candidate = Struct.new(:table, :table_index, :header_index, :headers, :rows, :contact_below, :known_headers, keyword_init: true) do
    def header_row_number
      table.rows.fetch(header_index).row_number
    end
  end

  def initialize(parsed)
    @parsed = parsed
  end

  def perform(header_row: nil, table_index: nil)
    return pinned(header_row, table_index.to_i) if header_row

    tables.each_with_index.flat_map { |table, index| table_candidates(table, index) }.max_by { |candidate| score(candidate) }
  end

  private

  def pinned(header_row, table_index)
    table = tables[table_index]
    header_index = table&.rows&.index { |row| row.row_number == header_row }
    raise Error, 'header_row_not_found' unless header_index

    build(table, table_index, header_index, contact_below: true)
  end

  def table_candidates(table, table_index)
    contact_rows = table.rows.map { |row| row.values.any? { |value| CampaignImports::ContactValues.contact?(value) } }
    last_contact_row = contact_rows.rindex(true)
    positions = table.rows.each_index.select { |index| !contact_rows[index] && header_values?(table.rows[index].values) }
    positions.first(HEADER_SCAN_LIMIT).map do |index|
      build(table, table_index, index, contact_below: last_contact_row.present? && last_contact_row > index)
    end
  end

  def build(table, table_index, header_index, contact_below:)
    headers = normalize_headers(table.rows.fetch(header_index).values)
    rows = table.rows.drop(header_index + 1).reject { |row| blank_row?(row) }
    Candidate.new(table: table, table_index: table_index, header_index: header_index, headers: headers, rows: rows,
                  contact_below: contact_below, known_headers: known_header_count(headers))
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
