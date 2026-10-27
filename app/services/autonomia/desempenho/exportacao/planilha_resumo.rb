# Aba Resumo da planilha do painel de desempenho (#2226), no padrão da planilha de referência:
# - linhas 1 e 2: título e contexto (agente, período, "dados até");
# - linhas 4 a 7: pares rótulo/valor, 4 por linha (A/B, D/E, G/H, J/K). Os valores que são soma viram fórmula viva
#   sobre as outras abas (com o valor calculado guardado, para abrir certo sem recálculo); contagem única (conversas,
#   tempo de resposta, mensagens) fica como valor do período, com nota;
# - linhas 9 a 12: nota amarela (o que o resultado não prova, quanto confiar, testes fora);
# - da linha 14 em diante: os 8 números com a explicação, as leituras rápidas e as definições.
module Autonomia::Desempenho::Exportacao::PlanilhaResumo
  LINHA_DA_NOTA = 9
  ALTURA_DA_NOTA = 4
  LARGURAS_DO_RESUMO = [28, 14, 3, 28, 14, 3, 28, 14, 3, 28, 14, 3].freeze

  def aba_resumo
    nova_aba(t('planilha.abas.resumo'), t('planilha.resumo_titulo', agente: meta.dig('agente', 'nome'))) do |sheet|
      pares_do_resumo.each_slice(4) { |pares| linha_de_pares(sheet, pares) }
      sheet.add_row([t('planilha.nota_fixos')], style: @estilos.contexto, types: :string, height: 16)
      nota_amarela(sheet)
      sheet.add_row([])
      numeros_no_resumo(sheet)
      leituras_no_resumo(sheet)
      sheet.column_widths(*LARGURAS_DO_RESUMO)
      deitar(sheet)
    end
  end

  private

  # [rótulo, valor, tipo] na ordem das células B4, E4, H4, K4, B5, ...
  def pares_do_resumo
    [*pares_de_volume, *pares_de_pessoa, *pares_de_qualidade, *pares_de_mensagens]
  end

  def referencia_do_periodo(id)
    letra_da_coluna = letra(colunas_por_periodo, id)
    "'#{nome_da_aba_por_periodo}'!#{letra_da_coluna}5:#{letra_da_coluna}#{ultima_linha_por_periodo}"
  end

  def pares_de_volume
    [[t('kpi.procuras'), formula("=SUBTOTAL(109,#{referencia_do_periodo('procuras')})", soma_da_evolucao('procuras')), :inteiro],
     [t('kpi.conversas'), kpi('conversas')['valor'].to_i, :inteiro],
     [nomes['compra'], formula("=SUM(#{referencia_do_periodo('compra')})", soma_da_evolucao('compra')), :inteiro],
     [nomes['fechou'], formula("=SUM(#{referencia_do_periodo('fecharam')})", soma_da_evolucao('fecharam')), :inteiro]]
  end

  def pares_de_pessoa
    precisavam = soma_da_evolucao('precisavam_pessoa')
    tiveram = soma_da_evolucao('tiveram_pessoa')
    [[t('planilha.taxa_fechou'), formula('=IFERROR(K4/H4,0)', fracao(parte(soma_da_evolucao('fecharam'), soma_da_evolucao('compra'))) || 0), :pct],
     [t('tabelas.precisavam'), formula("=SUM(#{referencia_do_periodo('precisavam_pessoa')})", precisavam), :inteiro],
     [t('tabelas.tiveram'), formula("=SUM(#{referencia_do_periodo('tiveram_pessoa')})", tiveram), :inteiro],
     [t('kpi.sem_pessoa'), formula('=E5-H5', precisavam - tiveram), :inteiro]]
  end

  def pares_de_qualidade
    duvidas = base_n('duvidas_resolvidas')
    [[t('kpi.perdas_evitaveis'), formula_das_perdas, :inteiro],
     [t('kpi.duvidas_resolvidas'), fracao(parte(duvidas['n'], duvidas['m'])), :pct],
     [t('kpi.tempo_resposta', nome: nome_do_agente), kpi('tempo_resposta')['valor'].to_i, :segundos],
     [t('planilha.testes_fora'), meta.dig('base', 'procuras_teste').to_i, :inteiro]]
  end

  # Conta os "sim" da coluna de perda evitável na aba Procuras.
  def formula_das_perdas
    perda = letra(colunas_das_procuras, 'perda')
    faixa = "'#{t('planilha.abas.procuras')}'!#{perda}5:#{perda}#{cabecalho_da_tabela_de_dados + [procuras_reais.size, 1].max}"
    formula("=COUNTIF(#{faixa},\"#{t('sim')}\")", procuras_reais.count { |procura| procura['perda_evitavel'] })
  end

  def pares_de_mensagens
    mensagens = meta.dig('base', 'mensagens').to_h
    [[t('planilha.mensagens_pessoas'), mensagens['contato'].to_i, :inteiro],
     [t('planilha.mensagens_agente', nome: nome_do_agente), mensagens['agente'].to_i, :inteiro],
     [t('planilha.mensagens_equipe'), mensagens['equipe'].to_i, :inteiro],
     [t('horarios.fora_do_horario'), fracao(@painel.dig('horarios', 'faixas', 'fora', 'pct')), :pct]]
  end

  def linha_de_pares(sheet, pares)
    valores = pares.flat_map { |rotulo, valor, _tipo| [rotulo, valor, nil] }
    tipos = pares.flat_map { |_rotulo, _valor, tipo| [:texto, tipo, :texto] }
    sheet.add_row(valores.map { |valor| texto_da_celula(valor) },
                  types: tipos.zip(valores).map { |tipo, valor| tipo_da_celula(tipo, valor) },
                  style: pares.flat_map { |_rotulo, _valor, tipo| [@estilos.rotulo, @estilos.valor(tipo), nil] },
                  **formulas_da_linha(valores), height: 30)
  end

  def nota_amarela(sheet)
    texto = [nomes['fechou_ressalva'], @painel.dig('confianca', 'leitura_geral'),
             t('planilha.testes_ficam_fora', n: numero(meta.dig('base', 'procuras_teste').to_i))].compact_blank.join("\n")
    vazios = Array.new(LARGURAS_DO_RESUMO.size - 1)
    ALTURA_DA_NOTA.times do |index|
      sheet.add_row([index.zero? ? texto : nil, *vazios], style: @estilos.nota, types: :string, height: 20)
    end
    sheet.merge_cells("A#{LINHA_DA_NOTA}:L#{LINHA_DA_NOTA + ALTURA_DA_NOTA - 1}")
  end

  def numeros_no_resumo(sheet)
    sheet.add_row([t('planilha.os_numeros')], style: @estilos.secao, types: :string, height: 20)
    numeros_do_painel.each do |item|
      texto = [item[:explicacao], item[:delta]].compact_blank.join(' · ')
      linha_de_texto(sheet, item[:rotulo], item[:valor], texto)
    end
    sheet.add_row([])
  end

  def leituras_no_resumo(sheet)
    sheet.add_row([t('planilha.leituras')], style: @estilos.secao, types: :string, height: 20)
    leituras_rapidas.each { |leitura| linha_de_texto(sheet, leitura[:titulo], nil, leitura[:texto]) }
    sheet.add_row([])
    sheet.add_row([t('planilha.definicoes')], style: @estilos.secao, types: :string, height: 20)
    Array(meta['definicoes']).each { |definicao| linha_de_texto(sheet, definicao['termo'], nil, definicao['texto']) }
  end

  # Rótulo em A, valor (texto) em B e o texto de C a L, mesclado.
  def linha_de_texto(sheet, rotulo, valor, texto)
    sheet.add_row([rotulo, valor, texto], style: [@estilos.rotulo, @estilos.valor(:texto), @estilos.texto_longo], types: :string,
                                          height: 30)
    sheet.merge_cells("C#{sheet.rows.size}:L#{sheet.rows.size}")
  end
end
