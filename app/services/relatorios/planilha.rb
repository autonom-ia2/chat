# Base das planilhas (.xlsx) dos relatórios (#1960). Cada aba tem o título, uma linha de contexto (período e data de
# geração) e uma tabela do Excel com o cabeçalho azul-escuro da plataforma, linhas zebradas, filtro e ordenação no
# cabeçalho, primeira linha congelada e impressão deitada. Os relatórios só dizem as colunas e as linhas.
#
# Tipos de coluna: :texto (sempre texto: "=..." não vira fórmula), :inteiro, :dinheiro, :data (data e hora já no
# fuso da conta), :dia (só a data). A tabela é a do Excel ("Formatar como Tabela"), não `auto_filter`, pelo mesmo
# motivo de Crm::Cards::XlsxExport: o caxlsx grava o filtro duas vezes e o Excel pede para reparar o arquivo.
class Relatorios::Planilha
  HEADER_ROW = 4 # 1 título, 2 contexto, 3 respiro, 4 cabeçalho
  COLUNA_SEM_NOME = 'Coluna'.freeze
  CELL_TYPES = { texto: :string, inteiro: :integer, dinheiro: :float, data: :time, dia: :date }.freeze

  def initialize
    @pacote = Axlsx::Package.new
    @pacote.use_shared_strings = true
    @estilos = Relatorios::PlanilhaEstilos.new(@pacote.workbook)
    @tabelas = 0
  end

  # `colunas`: [{ titulo:, tipo:, largura: }]; `linhas`: arrays na ordem das colunas.
  def aba(nome, titulo:, contexto:, colunas:, linhas:)
    @pacote.workbook.add_worksheet(name: nome.to_s.first(31)) do |sheet|
      cabecalho(sheet, titulo, contexto, colunas)
      linhas.each_with_index { |linha, index| linha_de_dados(sheet, colunas, linha, index.odd?) }
      acabamento(sheet, colunas, linhas.size)
    end
  end

  # Aba de resumo: rótulo e valor, um por linha, com o tipo de cada valor.
  def resumo(nome, titulo:, contexto:, itens:)
    colunas = [{ titulo: '', tipo: :texto, largura: 34 }, { titulo: '', tipo: :texto, largura: 22 }]
    @pacote.workbook.add_worksheet(name: nome.to_s.first(31)) do |sheet|
      titulo_e_contexto(sheet, titulo, contexto)
      itens.each { |rotulo, valor, tipo| linha_de_resumo(sheet, rotulo, valor, tipo || :texto) }
      sheet.column_widths(*colunas.pluck(:largura))
      sheet.sheet_view.show_grid_lines = false
    end
  end

  def gerar
    @pacote.to_stream.read
  end

  # O pacote, para validar o arquivo contra o schema do formato (specs).
  attr_reader :pacote

  private

  def cabecalho(sheet, titulo, contexto, colunas)
    titulo_e_contexto(sheet, titulo, contexto)
    sheet.add_row(cabecalhos_unicos(colunas.pluck(:titulo)), style: @estilos.cabecalho, types: colunas.map { :string }, height: 28)
  end

  # A tabela do Excel exige cabeçalhos diferentes (sem diferenciar maiúscula) e não vazios; repetido ganha " (2)",
  # " (3)"... Sem isso o Excel repara o arquivo e apaga a tabela (dois anúncios com o mesmo nome, por exemplo).
  def cabecalhos_unicos(titulos)
    usados = Set.new
    titulos.each_with_index.map do |titulo, index|
      base = titulo.to_s.strip.presence || "#{COLUNA_SEM_NOME} #{index + 1}"
      candidato = base
      numero = 1
      candidato = "#{base} (#{numero += 1})" while usados.include?(candidato.downcase)
      usados << candidato.downcase
      candidato
    end
  end

  def titulo_e_contexto(sheet, titulo, contexto)
    sheet.add_row([titulo], style: @estilos.titulo, types: [:string], height: 26)
    sheet.add_row([contexto], style: @estilos.contexto, types: [:string], height: 18)
    sheet.add_row([], height: 8)
  end

  def linha_de_dados(sheet, colunas, linha, zebra)
    sheet.add_row(linha, types: colunas.map { |coluna| CELL_TYPES.fetch(coluna[:tipo]) },
                         style: colunas.map { |coluna| @estilos.celula(coluna[:tipo], zebra: zebra) }, height: 20)
  end

  def linha_de_resumo(sheet, rotulo, valor, tipo)
    sheet.add_row([rotulo, valor], types: [:string, CELL_TYPES.fetch(tipo)],
                                   style: [@estilos.rotulo, @estilos.valor_de_resumo(tipo)], height: 22)
  end

  def acabamento(sheet, colunas, total)
    sheet.column_widths(*colunas.pluck(:largura))
    @tabelas += 1
    ultima = HEADER_ROW + [total, 1].max
    sheet.add_table("A#{HEADER_ROW}:#{Axlsx.col_ref(colunas.size - 1)}#{ultima}",
                    name: "Tabela#{@tabelas}", style_info: { name: 'TableStyleLight1', show_row_stripes: false })
    sheet.sheet_view.show_grid_lines = false
    congelar(sheet)
    sheet.page_setup.set(orientation: :landscape, fit_to_width: 1, fit_to_height: 0)
    sheet.workbook.add_defined_name("'#{sheet.name}'!$#{HEADER_ROW}:$#{HEADER_ROW}",
                                    name: '_xlnm.Print_Titles', local_sheet_id: sheet.index)
  end

  def congelar(sheet)
    sheet.sheet_view.pane do |pane|
      pane.state = :frozen
      pane.y_split = HEADER_ROW
      pane.top_left_cell = "A#{HEADER_ROW + 1}"
    end
  end
end
