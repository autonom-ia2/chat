# Planilha (.xlsx) do painel de desempenho do agente (#2226), no padrão da planilha de referência.
#
# Recebe o painel de UM período (contrato v2) e devolve os bytes. Não lê banco. Abas, na ordem: Resumo (pares
# rótulo/valor com fórmulas vivas sobre as outras abas, nota amarela, leituras e definições), Por dia ou Por semana,
# Por tema, Funil, Origem (e Anúncios, quando houver), Horários (7 × 24 com escala de cor), Procuras (uma linha por
# procura real, sem testes), Vendas perdidas, Cortes, Regras quebradas, Recomendações e Como ler.
#
# Toda aba de dados: título e contexto, cabeçalho azul-escuro, tabela do Excel (o filtro vem dela; nada de
# `auto_filter`, que o caxlsx grava duas vezes), cabeçalho congelado, formatos de número e impressão deitada.
class Autonomia::Desempenho::Exportacao::Planilha
  include Autonomia::Desempenho::Exportacao::Textos
  include Autonomia::Desempenho::Exportacao::Leituras
  include Autonomia::Desempenho::Exportacao::PlanilhaResumo
  include Autonomia::Desempenho::Exportacao::Planilha::Abas
  include Autonomia::Desempenho::Exportacao::Planilha::Listas
  include Autonomia::Desempenho::Exportacao::Planilha::Horarios
  include Autonomia::Desempenho::Exportacao::Planilha::AcoesELeitura
  include Autonomia::Desempenho::Exportacao::Planilha::PerdasECortes

  CABECALHO = 4 # 1 título, 2 contexto, 3 respiro, 4 cabeçalho da tabela
  COLUNAS_DO_TITULO = 12
  TIPOS = {
    texto: :string, texto_longo: :string, inteiro: :integer, pct: :float, decimal: :float, dinheiro: :float,
    data_hora: :time, dia: :date, segundos: :integer
  }.freeze
  COLUNA_SEM_NOME = 'Coluna'.freeze

  # Célula de fórmula com o valor já calculado, para abrir certo mesmo sem recálculo.
  Formula = Struct.new(:texto, :cache)

  def initialize(painel)
    @painel = Autonomia::Desempenho::Exportacao::Contrato.validar!(painel)
    @pacote = Axlsx::Package.new
    @pacote.use_shared_strings = true
    moeda = Autonomia::Desempenho::Exportacao::Textos::MOEDAS.fetch(@painel.dig('ticket', 'moeda').to_s, 'R$')
    @estilos = Autonomia::Desempenho::Exportacao::Planilha::Estilos.new(@pacote.workbook, moeda: moeda)
    @tabelas = 0
  end

  def gerar
    pacote.to_stream.read
  end

  # O pacote montado, para validar o arquivo contra o schema do formato (specs).
  def pacote
    montar unless @montada
    @pacote
  end

  private

  def montar
    @montada = true
    aba_resumo
    aba_por_periodo
    aba_por_tema
    aba_funil
    aba_origem
    aba_anuncios if anuncios?
    aba_horarios
    aba_procuras
    aba_perdas
    aba_cortes
    aba_regras
    aba_recomendacoes
    aba_como_ler
  end

  def anuncios?
    meta['anuncios_ligados'] && Array(@painel.dig('origem', 'anuncios')).any?
  end

  # `nota` entra na linha de contexto (ex.: o que a coluna Grupo inclui, na aba Procuras).
  def nova_aba(nome, titulo, nota: nil)
    @pacote.workbook.add_worksheet(name: nome.to_s.first(31)) do |sheet|
      vazios = Array.new(COLUNAS_DO_TITULO - 1)
      sheet.add_row([titulo, *vazios], style: @estilos.titulo, types: :string, height: 28)
      sheet.add_row([[contexto_da_planilha, nota].compact.join(' · '), *vazios], style: @estilos.contexto, types: :string, height: 18)
      sheet.add_row([], height: 8)
      ultima = Axlsx.col_ref(COLUNAS_DO_TITULO - 1)
      sheet.merge_cells("A1:#{ultima}1")
      sheet.merge_cells("A2:#{ultima}2")
      sheet.sheet_view.show_grid_lines = false
      yield sheet
    end
  end

  def contexto_da_planilha
    t('planilha.contexto', agente: meta.dig('agente', 'nome'), periodo: periodo_texto(meta['periodo']),
                           dados_ate: dia_hora(meta['dados_ate']))
  end

  # Cabeçalho (linha 4) + linhas + tabela do Excel. Devolve a última linha de dados.
  def tabela_de_dados(sheet, colunas, linhas)
    sheet.add_row(cabecalhos_unicos(colunas.pluck(:titulo)), style: @estilos.cabecalho, types: :string, height: 30)
    linhas.each { |linha| linha_de_dados(sheet, colunas, linha) }
    acabamento(sheet, colunas, linhas.size)
    CABECALHO + linhas.size
  end

  def linha_de_dados(sheet, colunas, linha, total: false)
    sheet.add_row(linha.map { |valor| texto_da_celula(valor) },
                  types: colunas.zip(linha).map { |item, valor| tipo_da_celula(item[:tipo], valor) },
                  style: colunas.map { |item| total ? @estilos.total(item[:tipo]) : @estilos.celula(item[:tipo]) },
                  **formulas_da_linha(linha), height: 18)
  end

  # O escape de "=" desligado só nas fórmulas, e o valor já calculado de cada uma.
  def formulas_da_linha(valores)
    { escape_formulas: valores.map { |valor| !valor.is_a?(Formula) }, formula_values: valores.map { |valor| cache_da_celula(valor) } }
  end

  def texto_da_celula(valor)
    valor.is_a?(Formula) ? valor.texto : valor
  end

  # Fórmula vai como texto que começa com "=" (com o escape desligado só nela); o resto pelo tipo da coluna.
  def tipo_da_celula(tipo, valor)
    valor.is_a?(Formula) ? :string : TIPOS.fetch(tipo)
  end

  def cache_da_celula(valor)
    valor.cache if valor.is_a?(Formula)
  end

  def acabamento(sheet, colunas, total)
    sheet.column_widths(*colunas.pluck(:largura))
    @tabelas += 1
    sheet.add_table("A#{CABECALHO}:#{Axlsx.col_ref(colunas.size - 1)}#{CABECALHO + [total, 1].max}",
                    name: "Tabela#{@tabelas}", style_info: { name: 'TableStyleLight1', show_row_stripes: true })
    congelar(sheet)
    deitar(sheet)
    repetir_cabecalho_na_impressao(sheet)
  end

  # Na impressão, o cabeçalho da tabela (linha 4) se repete em toda folha.
  def repetir_cabecalho_na_impressao(sheet)
    nome = sheet.name.split("'").join("''")
    @pacote.workbook.add_defined_name("'#{nome}'!$#{CABECALHO}:$#{CABECALHO}", local_sheet_id: sheet.index, name: '_xlnm.Print_Titles')
  end

  def deitar(sheet)
    sheet.page_setup.set(orientation: :landscape, fit_to_width: 1, fit_to_height: 0)
  end

  def congelar(sheet)
    sheet.sheet_view.pane do |pane|
      pane.state = :frozen
      pane.y_split = CABECALHO
      pane.top_left_cell = "A#{CABECALHO + 1}"
    end
  end

  # A tabela do Excel exige cabeçalhos diferentes (sem diferenciar maiúscula) e não vazios: dois cortes ou dois
  # anúncios com o mesmo nome ganham " (2)". Mesma regra de Relatorios::Planilha.
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

  def formula(texto, cache)
    Formula.new(texto, cache)
  end

  def cabecalho_da_tabela_de_dados
    CABECALHO
  end

  def coluna(titulo, tipo, largura)
    { titulo: titulo.to_s, tipo: tipo, largura: largura }
  end

  # [[chave, tipo, largura, id], ...]: 'compra' e 'fechou' viram o nome do negócio (do contrato); '%' fica igual; o resto
  # é chave de i18n. O id (padrão: a chave) serve para achar a letra da coluna.
  def colunas_de(lista)
    lista.map { |chave, tipo, largura, id| coluna(titulo_de(chave), tipo, largura).merge(id: id || chave) }
  end

  def titulo_de(chave)
    return nomes[chave].to_s if %w[compra fechou].include?(chave)

    chave == '%' ? chave : t(chave, nome: nome_do_agente)
  end

  def letra(colunas, id)
    Axlsx.col_ref(colunas.index { |item| item[:id] == id })
  end

  # Data e hora do contrato (texto já no fuso da conta) como hora "de parede", sem deslocar fuso no Excel.
  def hora_de_parede(data_hora)
    texto = data_hora.to_s
    Time.utc(texto[0, 4].to_i, texto[5, 2].to_i, texto[8, 2].to_i, texto[11, 2].to_i, texto[14, 2].to_i)
  end

  def dia_de(data)
    Date.new(data.to_s[0, 4].to_i, data.to_s[5, 2].to_i, data.to_s[8, 2].to_i)
  end

  def fracao(pct)
    pct.nil? ? nil : (pct.to_f / 100).round(4)
  end
end
