# Importar contatos (#1006): before importing, which cells do not fit the type of the contact
# attribute they would fill (a date attribute with "amanhã", a list without that option...).
# Those values are left out of that row; the rest of the row imports. The value itself is never
# shown, only the row and the attribute.
class ContactImports::AttributeProblems
  ROWS_SHOWN = 20

  # columns: ContactImports::AttributeColumns; rows: valid rows with :row_number and :extra_values.
  def initialize(columns, rows)
    @typed = columns.reject { |column| column.type == 'text' }.index_by(&:column)
    @rows = rows
  end

  def perform
    problems = @rows.flat_map { |row| row_problems(row) }
    {
      'count' => problems.size,
      'by_attribute' => problems.pluck('attribute').tally,
      'rows' => problems.first(ROWS_SHOWN)
    }
  end

  private

  def row_problems(row)
    row[:extra_values].to_h.filter_map do |header, raw|
      column = @typed[header]
      next unless column && column.cast(raw) == ContactImports::AttributeValue::INVALID

      { 'row_number' => row[:row_number], 'attribute' => column.label }
    end
  end
end
