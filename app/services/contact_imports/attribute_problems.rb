# Importar contatos (#1006): before importing, what happens to each extra-column value.
# - kept: the contact already has that attribute filled; it keeps its value (not a problem);
# - problems: the cell does not fit the type of the attribute (a date attribute with "amanhã",
#   a list without that option...). It is left out of that row; the rest of the row imports.
# The value itself is never shown, only the row and the attribute.
class ContactImports::AttributeProblems
  ROWS_SHOWN = 20

  # columns: ContactImports::AttributeColumns; rows: valid rows with :row_number and :extra_values;
  # existing: { row_number => custom_attributes } of the contacts the rows reuse.
  def initialize(columns, rows, existing = {})
    @columns = columns.index_by(&:column)
    @rows = rows
    @existing = existing
  end

  def perform
    kept = 0
    problems = @rows.flat_map do |row|
      outcomes = row_outcomes(row)
      kept += outcomes.count(:kept)
      outcomes.grep(Hash)
    end
    { 'count' => problems.size, 'kept' => kept, 'by_attribute' => problems.pluck('attribute').tally, 'rows' => problems.first(ROWS_SHOWN) }
  end

  private

  def row_outcomes(row)
    current = @existing.fetch(row[:row_number], {})
    row[:extra_values].to_h.filter_map do |header, raw|
      column = @columns[header]
      next unless column
      next :kept if current[column.key].to_s.strip.present?
      next unless column.cast(raw) == ContactImports::AttributeValue::INVALID

      { 'row_number' => row[:row_number], 'attribute' => column.label }
    end
  end
end
