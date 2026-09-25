# CSV da exportação (#682), como o do Orth: BOM UTF-8 e ponto e vírgula, que é o que o Excel em português abre em
# colunas. Decimal com vírgula pelo mesmo motivo.
module Autonomia::Prospecting::Export::CsvFile
  BOM = [0xFEFF].pack('U').freeze

  module_function

  def generate(rows)
    BOM + CSV.generate(col_sep: ';') do |csv|
      rows.each { |row| csv << row.map { |value| text(Autonomia::Prospecting::Export::Cell.safe(value)) } }
    end
  end

  def text(value)
    value.is_a?(Float) ? value.to_s.tr('.', ',') : value
  end
end
