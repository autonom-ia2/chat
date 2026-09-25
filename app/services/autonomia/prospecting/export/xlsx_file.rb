# Excel da exportação (#682), com a caxlsx, a mesma gem da planilha do CRM (Crm::Cards::XlsxExport). Texto vai como
# texto (`:string`), nunca como fórmula; número vai como número. O texto sai como o cliente o escreveria: o que começa
# como fórmula (Cell.formula_start?) leva o estilo quotePrefix em vez do apóstrofo que o CSV precisa, e o telefone +55
# aparece limpo. O cabeçalho vira uma Tabela do Excel, com os botões de filtro e ordenação.
module Autonomia::Prospecting::Export::XlsxFile
  SHEET_NAME = 'Leads'.freeze
  TABLE_NAME = 'LeadsExportados'.freeze
  # Neutro e sem listras, como a do CRM: só dá os botões do cabeçalho.
  TABLE_STYLE = { name: 'TableStyleLight1', show_row_stripes: false }.freeze
  DEFAULT_STYLE = 0

  module_function

  def generate(rows)
    package(rows).to_stream.read
  end

  # O pacote montado, exposto para validar o arquivo contra o schema do formato (specs).
  def package(rows)
    Axlsx::Package.new.tap do |pacote|
      styles = styles(pacote.workbook.styles)
      pacote.workbook.add_worksheet(name: SHEET_NAME) do |sheet|
        rows.each_with_index do |row, index|
          cell_styles = index.zero? ? row.map { styles[:header] } : data_styles(row, styles[:quoted])
          sheet.add_row(row, types: row.map { |value| cell_type(value) }, style: cell_styles, escape_formulas: true)
        end
        add_table(sheet, rows)
      end
    end
  end

  # O quotePrefix não é opção do add_style: o formato entra direto na lista de estilos de célula (cellXfs).
  def styles(stylesheet)
    {
      header: stylesheet.add_style(b: true),
      quoted: stylesheet.cellXfs << Axlsx::Xf.new(numFmtId: 0, fontId: 0, fillId: 0, borderId: 0, xfId: 0, quotePrefix: true)
    }
  end

  def data_styles(row, quoted)
    row.map { |value| Autonomia::Prospecting::Export::Cell.formula_start?(value) ? quoted : DEFAULT_STYLE }
  end

  # Não é sheet.auto_filter: a caxlsx 4.5 grava o _xlnm._FilterDatabase duas vezes e o Excel pede para reparar o arquivo.
  # Sem lead, a tabela cobre uma linha vazia: o Excel não aceita tabela só com cabeçalho.
  def add_table(sheet, rows)
    return if rows.empty?

    last_row = [rows.size, 2].max
    sheet.add_table("A1:#{Axlsx.col_ref(rows.first.size - 1)}#{last_row}", name: TABLE_NAME, style_info: TABLE_STYLE)
  end

  def cell_type(value)
    case value
    when Integer then :integer
    when Numeric then :float
    else :string
    end
  end
end
