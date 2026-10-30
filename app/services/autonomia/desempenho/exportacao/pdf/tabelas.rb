# Tabelas do PDF (#2226), no fim do arquivo e paginadas: por período (com "Total do trecho" em cada página e o
# asterisco do período em andamento), por tema, regras quebradas (com um exemplo), perdas evitáveis e conversas mais
# ativas. Cabeçalho azul-escuro, números à direita. A lista de todas as procuras fica só na planilha.
module Autonomia::Desempenho::Exportacao::Pdf::Tabelas
  # Teto de linhas por página (a fatia também respeita a altura livre) e da lista de perdas (a completa vai na planilha).
  LIMITE_DE_PERDAS = Autonomia::Desempenho::Exportacao::Pdf::Perdas::LIMITE_NA_TABELA
  POR_PAGINA = { tabela_periodo: 19, tabela_tema: 19, tabela_regras: 8, tabela_perdas: 16, tabela_ativas: 20 }.freeze
  LARGURAS = {
    tabela_periodo: nil,
    tabela_tema: [170, 62, 62, 80, 70, 62, 70, 70, 180, 78],
    tabela_regras: [230, 62, 52, 80, 480],
    tabela_perdas: [70, 70, 200, 140, 154, 270],
    tabela_ativas: [110, 90, 110, 110, 150, 150, 184]
  }.freeze
  # Colunas de número (à direita); as outras são texto.
  A_DIREITA = { tabela_tema: [1, 2, 3, 4, 5, 6, 7, 9], tabela_regras: [1, 2], tabela_perdas: [], tabela_ativas: [1, 2, 3] }.freeze

  def plano_das_tabelas
    POR_PAGINA.keys.filter_map do |secao|
      total = fatias_da_tabela(secao).size
      [secao, total] if total.positive?
    end
  end

  def pagina_tabela_periodo(pagina) = pagina_de_tabela(:tabela_periodo, pagina)
  def pagina_tabela_tema(pagina) = pagina_de_tabela(:tabela_tema, pagina)
  def pagina_tabela_regras(pagina) = pagina_de_tabela(:tabela_regras, pagina)
  def pagina_tabela_perdas(pagina) = pagina_de_tabela(:tabela_perdas, pagina)
  def pagina_tabela_ativas(pagina) = pagina_de_tabela(:tabela_ativas, pagina)

  # Tabela de uma vez (sem quebra de página). Opções: larguras, direita (colunas de número; padrão: todas menos a
  # 1ª), destaque ([linha, coluna] em verde), total (linha final em azul-claro e negrito) e tamanho.
  def tabela_simples(cabecalho, linhas, cima, **opcoes)
    tabela = montar_tabela(cabecalho, linhas, opcoes)
    destaque = opcoes[:destaque]
    tabela.cells[destaque[0] + 1, destaque[1]].style(text_color: serie('resultado', :texto), font_style: :bold) if destaque
    @doc.bounding_box([0, cima], width: largura) { tabela.draw }
    cima - tabela.height
  end

  private

  def montar_tabela(cabecalho, linhas, opcoes)
    tabela = @doc.make_table([cabecalho, *linhas, *([opcoes[:total]] if opcoes[:total])], **opcoes_da_tabela(opcoes))
    acabar_tabela(tabela, opcoes[:direita] || (1...cabecalho.size).to_a, opcoes[:total])
    tabela
  end

  def opcoes_da_tabela(opcoes)
    estilo = { size: opcoes[:tamanho] || 7.5, padding: [3.2, 5], borders: [:bottom], border_width: 0.5, border_color: cor(:linha),
               text_color: cor(:tinta) }
    { header: true, width: largura, cell_style: estilo, column_widths: opcoes[:larguras] }.compact
  end

  def acabar_tabela(tabela, direita, total)
    tabela.row(0).style(background_color: cor(:navy), text_color: cor(:branco), font_style: :semibold, valign: :center)
    direita.each { |coluna| tabela.column(coluna).style(align: :right) }
    tabela.row(-1).style(background_color: cor(:total), font_style: :bold) if total
  end

  def pagina_de_tabela(secao, pagina)
    cima = abrir_pagina(t("tabelas.#{secao}.titulo"), subtitulo_da_tabela(secao), pagina)
    fatia = fatias_da_tabela(secao)[pagina[:parte] - 1]
    total = secao == :tabela_periodo ? total_do_trecho(fatia) : nil
    cima = tabela_simples(cabecalho_da_tabela(secao), fatia.pluck(:celulas), cima, **opcoes_da_secao(secao), total: total)
    nota_da_tabela(secao, fatia, cima - 8, ultima: pagina[:parte] == pagina[:de])
  end

  def opcoes_da_secao(secao)
    { larguras: LARGURAS[secao], direita: A_DIREITA[secao], tamanho: secao == :tabela_regras ? 7 : 7.5 }
  end

  def subtitulo_da_tabela(secao)
    return t('tabelas.tabela_ativas.subtitulo', pct: pct(parte_das_ativas)) if secao == :tabela_ativas

    t("tabelas.#{secao}.subtitulo", unidade: t("tabelas.unidade_no_texto.#{unidade_da_evolucao}"), nome: nome_do_agente)
  end

  # A nota das perdas ("mostramos as primeiras N") vai só na última página da tabela.
  def nota_da_tabela(secao, fatia, cima, ultima:)
    return (nota_das_perdas(cima) if ultima) if secao == :tabela_perdas
    return unless secao == :tabela_periodo && fatia.any? { |linha| linha[:parcial] }

    escrever(t("evolucao.parcial_#{unidade_da_evolucao}"), 0, cima, largura, tamanho: 7.5, tinta: :apoio)
  end

  # Mesma base do "top 10" do painel: os pedidos de compra das conversas que mais pedem.
  def parte_das_ativas
    parte(Array(@painel['conversas_ativas']).sum { |linha| linha['compra'].to_i }, @painel.dig('funil', 'base'))
  end

  def linhas_da_tabela(secao)
    @linhas_da_tabela ||= {}
    @linhas_da_tabela[secao] ||= send("linhas_#{secao}")
  end

  # As chaves 'compra' e 'fechou' viram o nome do negócio (do contrato); '%' fica igual; o resto é i18n.
  COLUNAS = {
    tabela_tema: %w[tema procuras do_total compra fechou pct_fechou acerto erro_grave mais_trava vs_anterior],
    tabela_regras: %w[regra procuras % quase_sempre exemplo],
    tabela_perdas: %w[quando conversa por_que como_terminou motivos resumo],
    tabela_ativas: %w[conversa procuras compra fechou primeiro ultimo tema_frequente]
  }.freeze

  def cabecalho_da_tabela(secao)
    return cabecalho_por_periodo if secao == :tabela_periodo

    COLUNAS.fetch(secao).map { |chave| titulo_da_coluna(chave) }
  end

  def titulo_da_coluna(chave)
    return nomes[chave].to_s if %w[compra fechou].include?(chave)

    chave == '%' ? chave : t("tabelas.#{chave}", nome: nome_do_agente)
  end

  def cabecalho_por_periodo
    numeros = %w[procuras conversas_novas compra fechou pct_fechou precisavam tiveram].map { |chave| titulo_da_coluna(chave) }
    colunas = [t("tabelas.unidade.#{unidade_da_evolucao}"), *numeros]
    colunas += [t('tabelas.com_anuncio'), t('tabelas.sem_anuncio')] if meta['anuncios_ligados']
    colunas
  end

  CAMPOS_DO_PERIODO = %w[procuras conversas_novas compra fecharam].freeze
  CAMPOS_DA_PESSOA = %w[precisavam_pessoa tiveram_pessoa].freeze
  CAMPOS_DO_ANUNCIO = %w[com_anuncio sem_anuncio].freeze

  def linhas_tabela_periodo
    Array(@painel.dig('evolucao', 'pontos')).map do |ponto|
      { parcial: ponto['parcial'], ponto: ponto, celulas: celulas_do_periodo(ponto, rotulo_do_ponto(ponto)) }
    end
  end

  def rotulo_do_ponto(ponto)
    rotulo = ponto['inicio'] == ponto['fim'] ? data_longa(ponto['inicio']) : "#{dia_mes(ponto['inicio'])} a #{data_longa(ponto['fim'])}"
    ponto['parcial'] ? "#{rotulo}*" : rotulo
  end

  def celulas_do_periodo(ponto, rotulo)
    celulas = [rotulo, *CAMPOS_DO_PERIODO.map { |campo| numero(ponto[campo].to_i) }, pct(parte(ponto['fecharam'], ponto['compra'])),
               *CAMPOS_DA_PESSOA.map { |campo| numero(ponto[campo].to_i) }]
    celulas += CAMPOS_DO_ANUNCIO.map { |campo| numero(ponto[campo].to_i) } if meta['anuncios_ligados']
    celulas
  end

  def total_do_trecho(fatia)
    soma = (CAMPOS_DO_PERIODO + CAMPOS_DA_PESSOA + CAMPOS_DO_ANUNCIO).index_with { |campo| fatia.sum { |linha| linha[:ponto][campo].to_i } }
    celulas_do_periodo(soma, t('tabelas.total_do_trecho'))
  end

  def linhas_tabela_tema
    Array(@painel.dig('temas', 'ranking')).map do |tema|
      { celulas: [tema['nome'], numero(tema['procuras']), pct(tema['pct']), numero(tema['compra']), numero(tema['fecharam']),
                  pct(tema['taxa_pct']), pct(tema['acerto_pct']), pct(tema['erro_grave_pct']), trava_do_tema(tema).to_s, variacao_numerica(tema)] }
    end
  end

  def variacao_numerica(tema)
    return Autonomia::Desempenho::Exportacao::Textos::TRACO if tema['anterior_procuras'].nil?

    format('%+d', tema['procuras'].to_i - tema['anterior_procuras'].to_i)
  end

  def linhas_tabela_regras
    Array(@painel.dig('qualidade', 'regras')).map do |regra|
      exemplo = Array(regra['exemplos']).first
      { celulas: [[regra['nome'], regra['descricao']].compact_blank.join("\n"), numero(regra['procuras']), pct(regra['pct']),
                  regra['sistemica'] ? t('sim') : '', exemplo ? "#{prova_curta(exemplo)} — #{exemplo['resumo']}" : ''] }
    end
  end

  def linhas_tabela_perdas
    Array(@painel.dig('perdas', 'lista')).first(LIMITE_DE_PERDAS).map do |prova|
      motivos = Array(prova['motivo_ids']).map { |id| nome_de(catalogo, 'motivos', id) }.join(', ')
      { celulas: [dia_hora(prova['quando']), "##{prova['conversa']}", prova['por_que'].to_s,
                  nome_de(catalogo, 'resultados', prova['resultado_id']), motivos, prova['resumo'].to_s] }
    end
  end

  def linhas_tabela_ativas
    Array(@painel['conversas_ativas']).map do |linha|
      { celulas: ["##{linha['conversa']}", numero(linha['procuras']), numero(linha['compra']), numero(linha['fecharam']),
                  dia_hora(linha['primeira']), dia_hora(linha['ultima']), nome_de(catalogo, 'temas', linha['tema_id'])] }
    end
  end
end
