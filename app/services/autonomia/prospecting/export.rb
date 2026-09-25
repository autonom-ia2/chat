# Exportação dos leads de uma busca ou de uma lista (#682, frente A): a mesma tabela em CSV ou em Excel.
module Autonomia::Prospecting::Export
  FORMATS = {
    'csv' => { writer: 'CsvFile', content_type: 'text/csv; charset=utf-8' },
    'xlsx' => { writer: 'XlsxFile', content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }
  }.freeze

  module_function

  def formats
    FORMATS.keys
  end

  def generate(format, rows)
    const_get(FORMATS.fetch(format)[:writer]).generate(rows)
  end

  def content_type(format)
    FORMATS.fetch(format)[:content_type]
  end
end
