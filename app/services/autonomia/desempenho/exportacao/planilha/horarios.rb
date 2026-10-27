# Aba Horários da planilha do painel de desempenho (#2226): grade 7 × 24 (dia nas linhas, horas nas colunas) com a
# coluna Total =SUM(B5:Y5), a linha Total =SUM(B5:B11) e escala de cor de 3 pontos (branco → azul-claro → azul).
# Embaixo, a tabela das 4 faixas (no horário comercial, fora, fim de semana, noite).
module Autonomia::Desempenho::Exportacao::Planilha::Horarios
  FAIXAS_DO_DIA = %w[dentro fora fim_de_semana noite].freeze
  PRIMEIRA_LINHA = 5
  ULTIMA_HORA = 'Y'.freeze
  TOTAL = 'Z'.freeze

  def aba_horarios
    mapa = Array.new(7) { |dia| Array.new(24) { |hora| @painel.dig('horarios', 'mapa', dia, hora).to_i } }
    nova_aba(t('planilha.abas.horarios'), t('planilha.horarios_titulo', fuso: fuso_da_conta(meta['fuso']))) do |sheet|
      cabecalho_do_mapa(sheet)
      mapa.each_with_index { |horas, dia| linha_do_mapa(sheet, t('dias')[dia], horas, PRIMEIRA_LINHA + dia) }
      linha_total_do_mapa(sheet, mapa)
      escala_do_mapa(sheet)
      faixas_dos_horarios(sheet)
      # Larguras no fim: a tabela das faixas embaixo não pode desfazer as do mapa.
      sheet.column_widths(18, *Array.new(24, 5.5), 9)
      congelar(sheet)
      deitar(sheet)
    end
  end

  private

  def cabecalho_do_mapa(sheet)
    sheet.add_row([t('planilha.dia'), *(0..23).map(&:to_s), t('planilha.total')], style: @estilos.cabecalho, types: :string, height: 22)
  end

  def linha_do_mapa(sheet, dia, horas, linha)
    valores = [dia, *horas, formula("=SUM(B#{linha}:#{ULTIMA_HORA}#{linha})", horas.sum)]
    sheet.add_row(valores.map { |valor| valor.is_a?(Autonomia::Desempenho::Exportacao::Planilha::Formula) ? valor.texto : valor },
                  types: [:string, *Array.new(24, :integer), :string],
                  style: [@estilos.rotulo, *Array.new(24, @estilos.celula(:inteiro)), @estilos.total(:inteiro)],
                  escape_formulas: [true, *Array.new(24, true), false], formula_values: [nil, *Array.new(24), horas.sum], height: 18)
  end

  def linha_total_do_mapa(sheet, mapa)
    ultima = PRIMEIRA_LINHA + 6
    letras = (1..25).map { |index| Axlsx.col_ref(index) }
    somas = (0..23).map { |hora| mapa.sum { |horas| horas[hora] } } << mapa.flatten.sum
    sheet.add_row([t('planilha.total'), *letras.map { |letra| "=SUM(#{letra}#{PRIMEIRA_LINHA}:#{letra}#{ultima})" }],
                  types: :string, style: [@estilos.rotulo, *Array.new(25, @estilos.total(:inteiro))],
                  escape_formulas: [true, *Array.new(25, false)], formula_values: [nil, *somas], height: 18)
  end

  def escala_do_mapa(sheet)
    escala = Axlsx::ColorScale.new({ type: :min, val: 0, color: 'FFFFFFFF' }, { type: :percent, val: '50', color: 'FFCEE7FE' },
                                   { type: :max, val: 0, color: 'FF0090FF' })
    sheet.add_conditional_formatting("B#{PRIMEIRA_LINHA}:#{ULTIMA_HORA}#{PRIMEIRA_LINHA + 6}",
                                     type: :colorScale, priority: 2, color_scale: escala)
  end

  def faixas_dos_horarios(sheet)
    sheet.add_row([])
    sheet.add_row([t('planilha.faixas_titulo')], style: @estilos.secao, types: :string, height: 20)
    titulos = [t('horarios.faixa'), t('tabelas.procuras'), t('tabelas.do_total'), nomes['compra'], nomes['fechou'],
               t('tabelas.pct_fechou'), t('tabelas.precisavam'), t('tabelas.tiveram'), t('horarios.sem_pessoa')]
    sheet.add_row(titulos, style: @estilos.cabecalho, types: :string, height: 30)
    faixas = @painel.dig('horarios', 'faixas').to_h
    FAIXAS_DO_DIA.each { |chave| linha_da_faixa_do_dia(sheet, chave, faixas[chave].to_h) }
  end

  def linha_da_faixa_do_dia(sheet, chave, faixa)
    tipos = %i[texto inteiro pct inteiro inteiro pct inteiro inteiro inteiro]
    precisavam = faixa['precisavam_pessoa'].to_i
    tiveram = faixa['tiveram_pessoa'].to_i
    valores = [t("horarios.faixas.#{chave}"), faixa['procuras'].to_i, fracao(faixa['pct']), faixa['compra'].to_i,
               faixa['fecharam'].to_i, fracao(faixa['taxa_pct']), precisavam, tiveram, [precisavam - tiveram, 0].max]
    sheet.add_row(valores, types: tipos.map { |tipo| Autonomia::Desempenho::Exportacao::Planilha::TIPOS.fetch(tipo) },
                           style: tipos.map { |tipo| @estilos.celula(tipo) }, height: 18)
  end
end
