# Abas de números da planilha do painel de desempenho (#2226): Por dia/Por semana (com total por SUBTOTAL e barra de
# dados nas procuras), Por tema, Funil e Origem (e Anúncios). As taxas saem por fórmula sobre as colunas da própria
# linha, com o valor calculado guardado junto.
module Autonomia::Desempenho::Exportacao::Planilha::Abas
  AZUL = 'FF0090FF'.freeze
  PRIMEIRA = 5 # primeira linha de dados (logo abaixo do cabeçalho da tabela)
  COLUNAS_DO_PERIODO = [
    ['tabelas.procuras', :inteiro, 13, 'procuras'], ['tabelas.conversas_novas', :inteiro, 13, 'conversas_novas'],
    ['compra', :inteiro, 13, 'compra'], ['fechou', :inteiro, 13, 'fecharam'], ['tabelas.pct_fechou', :pct, 11, 'taxa'],
    ['tabelas.precisavam', :inteiro, 13, 'precisavam_pessoa'], ['tabelas.tiveram', :inteiro, 13, 'tiveram_pessoa']
  ].freeze
  COLUNAS_DO_ANUNCIO = [['tabelas.com_anuncio', :inteiro, 13, 'com_anuncio'], ['tabelas.sem_anuncio', :inteiro, 13, 'sem_anuncio']].freeze
  COLUNAS_DO_TEMA = [
    ['tabelas.tema', :texto, 30], ['tabelas.procuras', :inteiro, 11], ['tabelas.do_total', :pct, 11], ['compra', :inteiro, 14],
    ['fechou', :inteiro, 12], ['tabelas.pct_fechou', :pct, 11], ['tabelas.acerto', :pct, 12], ['tabelas.erro_grave', :pct, 12],
    ['tabelas.mais_trava', :texto, 28], ['planilha.periodo_anterior', :inteiro, 14], ['planilha.diferenca', :inteiro, 12]
  ].freeze
  COLUNAS_DO_FUNIL = [['planilha.etapa', :texto, 34], ['tabelas.procuras', :inteiro, 12], ['planilha.do_inicio', :pct, 14],
                      ['planilha.da_anterior', :pct, 16]].freeze
  COLUNAS_DA_ORIGEM = [
    ['planilha.grupo', :texto, 28], ['planilha.tipo', :texto, 18], ['tabelas.procuras', :inteiro, 12], ['tabelas.do_total', :pct, 11],
    ['compra', :inteiro, 14], ['fechou', :inteiro, 12], ['planilha.pct_fecham', :pct, 12]
  ].freeze
  COLUNAS_DOS_ANUNCIOS = [
    ['planilha.anuncio', :texto, 30], ['planilha.campanha', :texto, 24], ['tabelas.procuras', :inteiro, 12], ['compra', :inteiro, 14],
    ['fechou', :inteiro, 12], ['planilha.pct_fecham', :pct, 12], ['planilha.gasto', :dinheiro, 14], ['planilha.custo_por_fechou', :dinheiro, 18]
  ].freeze

  def unidade_da_planilha
    @painel.dig('evolucao', 'unidade') == 'semana' ? 'semana' : 'dia'
  end

  def nome_da_aba_por_periodo
    t("planilha.abas.por_#{unidade_da_planilha}")
  end

  def pontos_da_evolucao
    Array(@painel.dig('evolucao', 'pontos'))
  end

  # [{ id:, titulo:, tipo:, largura: }] da aba por período, na ordem.
  def colunas_por_periodo
    datas = [['planilha.inicio', :dia, 12, 'inicio']]
    datas << ['planilha.fim', :dia, 12, 'fim'] if unidade_da_planilha == 'semana'
    anuncio = meta['anuncios_ligados'] ? COLUNAS_DO_ANUNCIO : []
    colunas_de(datas + COLUNAS_DO_PERIODO + anuncio + [['planilha.observacao', :texto, 26, 'observacao']])
  end

  def ultima_linha_por_periodo
    cabecalho_da_tabela_de_dados + [pontos_da_evolucao.size, 1].max
  end

  def soma_da_evolucao(campo)
    pontos_da_evolucao.sum { |ponto| ponto[campo].to_i }
  end

  def aba_por_periodo
    colunas = colunas_por_periodo
    titulo = t('planilha.por_periodo_titulo', unidade: t("tabelas.unidade_no_texto.#{unidade_da_planilha}"))
    nova_aba(nome_da_aba_por_periodo, titulo) do |sheet|
      linhas = pontos_da_evolucao.each_with_index.map { |ponto, index| linha_do_periodo(colunas, ponto, PRIMEIRA + index) }
      ultima = tabela_de_dados(sheet, colunas, linhas)
      linha_de_dados(sheet, colunas.map { |item| item.merge(tipo: item[:tipo] == :dia ? :texto : item[:tipo]) },
                     total_do_periodo(colunas, ultima), total: true)
      procuras = letra(colunas, 'procuras')
      sheet.add_conditional_formatting("#{procuras}#{PRIMEIRA}:#{procuras}#{[ultima, PRIMEIRA].max}",
                                       type: :dataBar, priority: 1, data_bar: Axlsx::DataBar.new(color: AZUL))
    end
  end

  private

  def linha_do_periodo(colunas, ponto, linha)
    colunas.map do |item|
      case item[:id]
      when 'inicio', 'fim' then dia_de(ponto[item[:id]])
      when 'taxa' then formula_de_taxa(colunas, linha, parte(ponto['fecharam'], ponto['compra']))
      when 'observacao' then ponto['parcial'] ? t("evolucao.parcial_#{unidade_da_planilha}") : nil
      else ponto[item[:id]].to_i
      end
    end
  end

  # % fechou = fecharam / compra da mesma linha (vazio quando não houve pedido de compra).
  def formula_de_taxa(colunas, linha, pct_calculado)
    fecharam = "#{letra(colunas, 'fecharam')}#{linha}"
    compra = "#{letra(colunas, 'compra')}#{linha}"
    formula("=IF(#{compra}=0,\"\",#{fecharam}/#{compra})", pct_calculado.nil? ? '' : fracao(pct_calculado))
  end

  def total_do_periodo(colunas, ultima)
    colunas.each_with_index.map do |item, index|
      next t('planilha.total') if index.zero?
      next formula_de_taxa(colunas, ultima + 1, parte(soma_da_evolucao('fecharam'), soma_da_evolucao('compra'))) if item[:id] == 'taxa'

      subtotal_da_coluna(colunas, item, ultima) if item[:tipo] == :inteiro
    end
  end

  def subtotal_da_coluna(colunas, item, ultima)
    coluna = letra(colunas, item[:id])
    formula("=SUBTOTAL(109,#{coluna}#{PRIMEIRA}:#{coluna}#{ultima})", soma_da_evolucao(item[:id]))
  end

  def aba_por_tema
    linhas = Array(@painel.dig('temas', 'ranking')).each_with_index.map { |tema, index| linha_do_tema(tema, PRIMEIRA + index) }
    nova_aba(t('planilha.abas.por_tema'), t('planilha.por_tema_titulo')) { |sheet| tabela_de_dados(sheet, colunas_de(COLUNAS_DO_TEMA), linhas) }
  end

  def linha_do_tema(tema, linha)
    trava = trava_do_tema(tema)
    [tema['nome'], tema['procuras'].to_i, fracao(tema['pct']), tema['compra'].to_i, tema['fecharam'].to_i,
     formula("=IF(D#{linha}=0,\"\",E#{linha}/D#{linha})", fracao(tema['taxa_pct']) || ''),
     fracao(tema['acerto_pct']), fracao(tema['erro_grave_pct']), trava, tema['anterior_procuras'], diferenca_do_tema(tema, linha)]
  end

  def diferenca_do_tema(tema, linha)
    diferenca = tema['anterior_procuras'] && (tema['procuras'].to_i - tema['anterior_procuras'].to_i)
    formula("=IF(J#{linha}=\"\",\"\",B#{linha}-J#{linha})", diferenca || '')
  end

  def aba_funil
    linhas = Array(@painel.dig('funil', 'etapas')).each_with_index.map { |etapa, index| linha_do_funil(etapa, PRIMEIRA + index) }
    nova_aba(t('planilha.abas.funil'), t('planilha.funil_titulo')) { |sheet| tabela_de_dados(sheet, colunas_de(COLUNAS_DO_FUNIL), linhas) }
  end

  def linha_do_funil(etapa, linha)
    anterior = formula("=IFERROR(B#{linha}/B#{linha - 1},0)", fracao(etapa['taxa_da_anterior']) || 0) if linha > PRIMEIRA
    [etapa['nome'], etapa['procuras'].to_i, formula("=IFERROR(B#{linha}/$B$#{PRIMEIRA},0)", fracao(etapa['pct_do_inicio']) || 0), anterior]
  end

  def aba_origem
    linhas = Array(@painel.dig('origem', 'grupos')).each_with_index.map { |grupo, index| linha_da_origem(grupo, PRIMEIRA + index) }
    nova_aba(t('planilha.abas.origem'), t('planilha.origem_titulo')) { |sheet| tabela_de_dados(sheet, colunas_de(COLUNAS_DA_ORIGEM), linhas) }
  end

  def linha_da_origem(grupo, linha)
    [grupo['nome'], t("planilha.tipo_origem.#{grupo['tipo']}", default: grupo['tipo'].to_s), grupo['procuras'].to_i, fracao(grupo['pct']),
     grupo['compra'].to_i, grupo['fecharam'].to_i, formula("=IF(E#{linha}=0,\"\",F#{linha}/E#{linha})", fracao(grupo['taxa_pct']) || '')]
  end

  def aba_anuncios
    linhas = Array(@painel.dig('origem', 'anuncios')).each_with_index.map { |anuncio, index| linha_do_anuncio(anuncio, PRIMEIRA + index) }
    nova_aba(t('planilha.abas.anuncios'), t('planilha.anuncios_titulo')) do |sheet|
      tabela_de_dados(sheet, colunas_de(COLUNAS_DOS_ANUNCIOS), linhas)
    end
  end

  def linha_do_anuncio(anuncio, linha)
    [anuncio['nome'], anuncio['campanha'], anuncio['procuras'].to_i, anuncio['compra'].to_i, anuncio['fecharam'].to_i,
     formula("=IF(D#{linha}=0,\"\",E#{linha}/D#{linha})", fracao(anuncio['taxa_pct']) || ''), anuncio['gasto'],
     formula("=IF(OR(G#{linha}=\"\",E#{linha}=0),\"\",G#{linha}/E#{linha})", anuncio['custo_por_fechou'] || '')]
  end
end
