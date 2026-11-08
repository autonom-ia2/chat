# Páginas "Como ler" do PDF (#2226). Na 1ª, as definições (do dado) e o que estes números não provam (frases fixas,
# a ressalva do resultado e os avisos do período). Na 2ª, quanto confiar: a conferência campo a campo, o método e a
# leitura geral, com espaço para a tabela inteira.
module Autonomia::Desempenho::Exportacao::Pdf::ComoLer
  ALTURA_DOS_CARTOES = 330
  COLUNAS_DA_CONFIANCA = [0, 260, 360, 440, 760].freeze # campo, acertos, %, barra, leitura
  LINHA_DA_CONFIANCA = 18
  LEITURA = { 'firme' => 'resultado', 'otimista' => 'tempo', 'fraca' => 'alerta' }.freeze

  def pagina_como_ler(pagina)
    cima = abrir_pagina(t('como_ler.titulo'), t('como_ler.subtitulo'), pagina)
    return pagina_de_confianca(cima) if pagina[:parte] == 2

    metade = (largura - 16) / 2.0
    listas = [[t('como_ler.como_ler'), linhas_de_como_ler], [t('como_ler.nao_provam'), linhas_do_que_nao_prova]]
    altura = listas.map { |_titulo, linhas| altura_da_lista(linhas, metade) }.max.clamp(..ALTURA_DOS_CARTOES)
    listas.each_with_index { |(titulo, linhas), index| cartao_de_lista(titulo, linhas, [index * (metade + 16), cima, metade], altura) }
  end

  def pagina_de_confianca(cima)
    geral = @painel.dig('confianca', 'leitura_geral')
    cima = ressalva(geral, 0, cima, largura) - 12 if geral.present?
    quanto_confiar(cima)
  end

  private

  def linhas_de_como_ler
    definicoes = Array(meta['definicoes']).map do |definicao|
      "<b>#{CGI.escapeHTML(definicao['termo'].to_s)}</b>: #{CGI.escapeHTML(definicao['texto'].to_s)}"
    end
    definicoes + [t('como_ler.testes', n: numero(meta.dig('base', 'procuras_teste').to_i))]
  end

  def linhas_do_que_nao_prova
    fixas = Autonomia::Desempenho::Exportacao::Textos::NAO_PROVAM.map { |chave| t("como_ler.nao_prova.#{chave}") }
    fixas << CGI.escapeHTML(nomes['fechou_ressalva']) if nomes['fechou_ressalva'].present?
    fixas + Array(@painel['avisos']).filter_map { |aviso| texto_do_aviso(aviso) }
  end

  def texto_da_lista(linhas)
    linhas.map { |linha| "•  #{linha}" }.join("\n")
  end

  # Os dois cartões têm a altura do maior texto (até ALTURA_DOS_CARTOES), não a página inteira.
  def altura_da_lista(linhas, largura_do_cartao)
    trechos = Prawn::Text::Formatted::Parser.format(texto_da_lista(linhas))
    @doc.height_of_formatted(trechos, width: largura_do_cartao - 24, size: 8.5, leading: 3) + 48
  end

  # caixa = [esq, cima, largura].
  def cartao_de_lista(titulo, linhas, caixa, altura)
    esq, cima, largura_total = caixa
    cartao(esq, cima, largura_total, altura)
    escrever_pilha([[titulo, 10, { tamanho: 10, estilo: :semibold }],
                    [texto_da_lista(linhas), 28, { tamanho: 8.5, altura: altura - 36, formatado: true, entrelinha: 3 }]],
                   esq + 12, cima, largura_total - 24)
  end

  def cabecalho_da_confianca(cima)
    faixa(0, cima, largura, 16, cor(:navy))
    [t('como_ler.campo'), t('como_ler.acertos'), t('como_ler.acerto'), '', t('como_ler.leitura_coluna')].each_with_index do |titulo, index|
      escrever(titulo, COLUNAS_DA_CONFIANCA[index] + 6, cima - 4.5, 200, tamanho: 7.5, estilo: :semibold, tinta: :branco)
    end
    cima - 16
  end

  def linha_de_confianca_no_pdf(campo, cima)
    cor_da_leitura = LEITURA.fetch(campo['leitura'], 'neutro')
    textos_da_confianca(campo, cor_da_leitura).each_with_index do |(texto, largura_do_texto, opcoes), index|
      escrever(texto, COLUNAS_DA_CONFIANCA[index] + 6, cima - 5, largura_do_texto, **opcoes) if texto
    end
    barra(COLUNAS_DA_CONFIANCA[3] + 6, cima - 6, 300, campo['acerto_pct'].to_f / 100, serie: cor_da_leitura, altura: 6)
    linha_fina(0, largura, cima - LINHA_DA_CONFIANCA)
    cima - LINHA_DA_CONFIANCA
  end

  def textos_da_confianca(campo, cor_da_leitura)
    [[campo['nome'], 250, { tamanho: 8, altura: 10 }],
     [t('como_ler.certos', n: numero(campo['certos']), m: numero(campo['total'])), 90, { tamanho: 8 }],
     [pct(campo['acerto_pct']), 70, { tamanho: 8, estilo: :semibold }], [nil, 0, {}],
     [t("como_ler.leitura.#{campo['leitura']}", default: campo['leitura'].to_s), 130,
      { tamanho: 8, estilo: :semibold, tinta: serie(cor_da_leitura, :texto) }]]
  end

  def quanto_confiar(cima)
    confianca = @painel['confianca'].to_h
    escrever(t('como_ler.quanto_confiar'), 0, cima, largura, tamanho: 10, estilo: :semibold)
    escrever([t('como_ler.conferimos', n: numero(confianca['conferidas'])), confianca['metodo']].compact.join(' '),
             0, cima - 14, largura, tamanho: 7.5, tinta: :apoio, altura: 20)
    campos = Array(confianca['campos'])
    return cima - 38 if campos.empty?

    cima = cabecalho_da_confianca(cima - 38)
    campos.reduce(cima) { |topo, campo| linha_de_confianca_no_pdf(campo, topo) }
  end
end
