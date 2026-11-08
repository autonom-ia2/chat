# Abas "Vendas perdidas" e "Cortes" da planilha do painel de desempenho (#2226). A primeira traz a lista completa
# das perdas por causa corrigível (o PDF mostra só as primeiras); a segunda, cada detalhe do pedido (corte) com
# quantas procuras, quantas eram pedido de compra e quantas fecharam.
module Autonomia::Desempenho::Exportacao::Planilha::PerdasECortes
  COLUNAS_DAS_PERDAS = [
    ['tabelas.quando', :data_hora, 17], ['tabelas.conversa', :inteiro, 10], ['tabelas.por_que', :texto_longo, 44],
    ['tabelas.como_terminou', :texto, 26], ['tabelas.motivos', :texto, 30], ['tabelas.resumo', :texto_longo, 60]
  ].freeze

  def aba_perdas
    linhas = Array(@painel.dig('perdas', 'lista')).map { |prova| linha_da_perda(prova) }
    nova_aba(t('planilha.abas.perdas'), t('planilha.perdas_titulo')) do |sheet|
      tabela_de_dados(sheet, colunas_de(COLUNAS_DAS_PERDAS), linhas)
    end
  end

  def aba_cortes
    cortes = Array(@painel['cortes'])
    return if cortes.empty?

    linhas = cortes.flat_map { |corte| Array(corte['ranking']).map { |item| linha_do_corte(corte, item) } }
    nova_aba(t('planilha.abas.cortes'), t('planilha.cortes_titulo')) do |sheet|
      tabela_de_dados(sheet, colunas_dos_cortes, linhas)
    end
  end

  private

  def linha_da_perda(prova)
    motivos = Array(prova['motivo_ids']).map { |id| nome_de(catalogo, 'motivos', id) }.join(', ')
    [hora_de_parede(prova['quando']), prova['conversa'].to_i, prova['por_que'].to_s,
     nome_de(catalogo, 'resultados', prova['resultado_id']), motivos, prova['resumo'].to_s]
  end

  def colunas_dos_cortes
    colunas_de([['planilha.corte', :texto, 24], ['planilha.valor_do_corte', :texto, 30], ['tabelas.procuras', :inteiro, 11],
                ['%', :pct, 9], ['compra', :inteiro, 14], ['fechou', :inteiro, 12], ['tabelas.pct_fechou', :pct, 11]])
  end

  def linha_do_corte(corte, item)
    [corte['nome'].presence || t('sem_nome'), item['nome'].presence || t('sem_nome'), item['procuras'].to_i, fracao(item['pct']),
     item['compra'].to_i, item['fecharam'].to_i, fracao(item['taxa_pct'])]
  end
end
