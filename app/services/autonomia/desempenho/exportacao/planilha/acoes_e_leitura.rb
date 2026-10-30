# Abas finais da planilha do painel de desempenho (#2226): Recomendações (do sinal à ação) e Como ler (a conferência
# campo a campo com a % por fórmula, as definições e o que os números não provam).
module Autonomia::Desempenho::Exportacao::Planilha::AcoesELeitura
  COLUNAS_DAS_RECOMENDACOES = [
    %w[titulo texto_longo 34], %w[frente texto 18], %w[problema texto_longo 44], %w[numeros texto_longo 44], %w[conversas texto 30],
    %w[instrucao texto_longo 44], %w[sistema texto_longo 40], %w[equipe texto_longo 40], %w[ganho_fechamentos inteiro 14],
    %w[ganho_valor dinheiro 16], %w[ganho_periodo texto_longo 30],
    %w[conta texto_longo 40], %w[pronto texto 18], %w[falta texto_longo 34]
  ].freeze
  COLUNAS_DA_CONFIANCA = [['como_ler.campo', :texto, 30], ['planilha.certos', :inteiro, 10], ['planilha.total', :inteiro, 10],
                          ['como_ler.acerto', :pct, 11], ['como_ler.leitura_coluna', :texto, 14], ['planilha.afeta', :texto_longo, 60]].freeze

  def aba_recomendacoes
    colunas = COLUNAS_DAS_RECOMENDACOES.map { |id, tipo, largura| coluna(t("planilha.recomendacao.#{id}"), tipo.to_sym, largura.to_i) }
    linhas = Array(@painel['recomendacoes']).map { |recomendacao| linha_da_recomendacao(recomendacao) }
    nova_aba(t('planilha.abas.recomendacoes'), t('planilha.recomendacoes_titulo'), nota: recomendacoes_de) do |sheet|
      tabela_de_dados(sheet, colunas, linhas)
    end
  end

  def aba_como_ler
    linhas = Array(@painel.dig('confianca', 'campos')).each_with_index.map { |campo, index| linha_de_confianca(campo, index + 5) }
    nova_aba(t('planilha.abas.como_ler'), t('planilha.como_ler_titulo')) do |sheet|
      colunas = colunas_de(COLUNAS_DA_CONFIANCA)
      ultima = tabela_de_dados(sheet, colunas, linhas)
      sheet.add_row([]) while sheet.rows.size < ultima + 2
      textos_de_como_ler(sheet)
      # Larguras no fim: os textos embaixo não podem desfazer as da tabela.
      sheet.column_widths(*colunas.pluck(:largura))
    end
  end

  private

  # #2301: sugestões de outras datas (as últimas do mesmo período) dizem as datas delas, como na tela.
  def recomendacoes_de
    datas = meta['recomendacoes_de']
    return nil if datas.blank? || Array(@painel['recomendacoes']).empty?

    t('planilha.recomendacoes_de', inicio: dia_mes(datas['inicio']), fim: data_longa(datas['fim']))
  end

  def linha_da_recomendacao(recomendacao)
    ganho = recomendacao['ganho'].to_h
    [recomendacao['titulo'], frente_da_recomendacao(recomendacao['frente']), recomendacao['problema'],
     recomendacao['numeros'], Array(recomendacao['conversas']).map { |prova| prova_curta(prova) }.join(', '), recomendacao['instrucao'],
     recomendacao['sistema'], recomendacao['equipe'], ganho['fechamentos'], ganho['valor'], periodo_da_coluna(ganho), ganho['conta'],
     t("planilha.pronto.#{recomendacao['pronto']}", default: recomendacao['pronto'].to_s), recomendacao['falta']]
  end

  # "30 dias (27/09 a 26/10)" ou, quando a conta usou o histórico, "Neste período ainda não dá para estimar. Histórico
  # completo: 4 meses (25/06 a 26/10)". Sem ganho, vazio.
  def periodo_da_coluna(ganho)
    return nil if ganho['fechamentos'].nil? && ganho['valor'].nil?

    t(ganho['historico'] ? 'planilha.ganho_periodo_historico' : 'planilha.ganho_periodo', **periodo_do_ganho(ganho))
  end

  def linha_de_confianca(campo, linha)
    afeta = lista(Array(campo['afeta']).map { |secao| t("secoes.#{secao}") })
    [campo['nome'], campo['certos'].to_i, campo['total'].to_i, formula("=IFERROR(B#{linha}/C#{linha},0)", fracao(campo['acerto_pct']) || 0),
     t("como_ler.leitura.#{campo['leitura']}", default: campo['leitura'].to_s), afeta]
  end

  def textos_de_como_ler(sheet)
    confianca = @painel['confianca'].to_h
    secao_de_texto(sheet, t('como_ler.quanto_confiar'), [[t('como_ler.conferimos', n: numero(confianca['conferidas'])), confianca['metodo']],
                                                         [nil, confianca['leitura_geral']]])
    secao_de_texto(sheet, t('como_ler.como_ler'), Array(meta['definicoes']).map { |definicao| definicao.values_at('termo', 'texto') })
    secao_de_texto(sheet, t('como_ler.nao_provam'), linhas_do_que_nao_prova_na_planilha)
  end

  # #2301: com os avisos da leitura automática (parada, pendentes, não lidas, instrução), como na tela e no PDF.
  def linhas_do_que_nao_prova_na_planilha
    fixas = Autonomia::Desempenho::Exportacao::Textos::NAO_PROVAM.map { |chave| [nil, t("como_ler.nao_prova.#{chave}")] }
    fixas << [nil, nomes['fechou_ressalva']] if nomes['fechou_ressalva'].present?
    fixas + avisos_da_leitura.filter_map { |aviso| texto_do_aviso(aviso)&.then { |texto| [nil, texto] } }
  end

  def avisos_da_leitura = Array(@painel['avisos']).select { |aviso| aviso['id'].to_s.start_with?('leitura_') }

  def secao_de_texto(sheet, titulo, linhas)
    sheet.add_row([titulo], style: @estilos.secao, types: :string, height: 20)
    linhas.each do |termo, texto|
      sheet.add_row([termo, texto], style: [@estilos.rotulo, @estilos.texto_longo], types: :string, height: 30)
      sheet.merge_cells("B#{sheet.rows.size}:F#{sheet.rows.size}")
    end
    sheet.add_row([])
  end
end
