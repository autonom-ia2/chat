# Páginas de ações do PDF (#2226): do sinal à ação. Quatro cartões por página, com a borda de cima na cor da frente:
# título, problema, a prova (números e conversas), o que mudar (na instrução / no sistema) e o ganho estimado com a
# conta. As colunas "Já dá para usar" e "Precisa de mais dado" entram embaixo dos últimos cartões quando todos cabem
# inteiros (medidos antes de desenhar); senão ganham página própria. Texto que não cabe termina em "…", nunca some.
module Autonomia::Desempenho::Exportacao::Pdf::Acoes
  POR_PAGINA = 4
  FRENTES = { 'instrucao' => 'volume', 'sistema' => 'preparo', 'equipe' => 'tempo', 'anuncio' => 'resultado' }.freeze
  ALTURA_DAS_COLUNAS = 118
  VAO = 12
  TEXTO_DA_ACAO = { tamanho: 7.5, estilo: :normal, tinta: :tinta }.freeze

  def paginas_de_acoes
    fatias = fatias_de_acoes.size
    return 1 if fatias.zero?

    prontidao_em_pagina_propria? ? fatias + 1 : fatias
  end

  def pagina_acoes(pagina)
    cima = abrir_pagina(t('acoes.titulo'), subtitulo_das_acoes, pagina)
    return vazio(0, cima, largura) if recomendacoes.empty?

    fatia = fatias_de_acoes[pagina[:parte] - 1]
    return colunas_de_prontidao(cima, altura_da_prontidao.clamp(ALTURA_DAS_COLUNAS, cima)) if fatia.nil?

    cartoes_da_pagina(fatia, cima, ultima: pagina[:parte] == fatias_de_acoes.size && !prontidao_em_pagina_propria?)
  end

  private

  def recomendacoes
    Array(@painel['recomendacoes'])
  end

  # #2301: sugestões de outras datas (as últimas do mesmo período) dizem as datas delas, como na tela.
  def subtitulo_das_acoes
    datas = @painel.dig('meta', 'recomendacoes_de')
    return t('acoes.subtitulo') if datas.blank? || recomendacoes.empty?

    t('acoes.subtitulo_de_outras_datas', inicio: dia_mes(datas['inicio']), fim: data_longa(datas['fim']))
  end

  # Os cartões da página e, na última (quando cabem), as colunas de prontidão embaixo.
  def cartoes_da_pagina(fatia, cima, ultima:)
    altura = ultima ? cima - ALTURA_DAS_COLUNAS - VAO : cima
    fatia.each_with_index { |recomendacao, index| cartao_de_acao(recomendacao, [index * (largura_da_acao + VAO), cima], altura) }
    colunas_de_prontidao(ALTURA_DAS_COLUNAS, ALTURA_DAS_COLUNAS) if ultima
  end

  def fatias_de_acoes
    recomendacoes.each_slice(POR_PAGINA).to_a
  end

  # As colunas de prontidão só dividem a página com os últimos cartões quando todos eles cabem inteiros acima delas.
  def prontidao_em_pagina_propria?
    return @prontidao_em_pagina_propria unless @prontidao_em_pagina_propria.nil?

    documento
    livre = topo - 50 - ALTURA_DAS_COLUNAS - VAO
    @prontidao_em_pagina_propria = fatias_de_acoes.last.to_a.any? { |recomendacao| altura_da_acao(recomendacao) > livre }
  end

  # A altura que o cartão inteiro pede, com as mesmas medidas do desenho.
  def altura_da_acao(recomendacao)
    prova = texto_da_prova(recomendacao)
    altura = 38 + altura_no_cartao(recomendacao['titulo'], 9.5, :semibold) + altura_no_cartao(recomendacao['problema'], 7.5)
    altura += altura_do_texto(prova, largura_da_acao - 32, 7) + 26 if prova.present?
    altura += textos_das_mudancas(recomendacao).sum { |linha| altura_no_cartao(linha, 7.5) }
    altura + textos_do_ganho(recomendacao['ganho'].to_h).sum { |linha, tamanho| altura_no_cartao(linha, tamanho) }
  end

  def altura_no_cartao(texto, tamanho, estilo = :normal)
    texto.blank? ? 0 : altura_do_texto(texto, largura_da_acao - 20, tamanho, estilo: estilo) + 6
  end

  def largura_da_acao
    (largura - (VAO * (POR_PAGINA - 1))) / POR_PAGINA.to_f
  end

  # ponto = [esq, cima]. O texto corre para baixo e para no fim do cartão.
  def cartao_de_acao(recomendacao, ponto, altura)
    esq, cima = ponto
    moldura_da_acao(recomendacao['frente'], ponto, altura)
    @fluxo = { esq: esq + 10, largura: largura_da_acao - 20, fim: cima - altura + 8 }
    topo = correr(recomendacao['titulo'], cima - 30, tamanho: 9.5, estilo: :semibold)
    topo = correr(recomendacao['problema'], topo - 4, tinta: :apoio)
    topo = prova_da_acao(recomendacao, topo - 6)
    ganho_da_acao(recomendacao['ganho'].to_h, mudancas_da_acao(recomendacao, topo - 6) - 6)
  end

  def moldura_da_acao(frente, ponto, altura)
    esq, cima = ponto
    cor_da_frente = FRENTES.fetch(frente, 'neutro')
    cartao(esq, cima, largura_da_acao, altura)
    faixa(esq + 6, cima, largura_da_acao - 12, 3, serie(cor_da_frente))
    pilula(frente_da_recomendacao(frente), esq + 10, cima - 10, fundo: serie(cor_da_frente, :trilho), tinta: serie(cor_da_frente, :texto),
                                                                tamanho: 7)
  end

  # Escreve no fluxo do cartão atual e devolve o y logo abaixo. O que não cabe termina em "…" (nunca some calado).
  def correr(texto, cima, **opcoes)
    opcoes = TEXTO_DA_ACAO.merge(opcoes)
    livre = cima - @fluxo[:fim]
    return cima if texto.blank? || livre < opcoes[:tamanho]

    texto = caber(texto, livre, opcoes)
    altura = altura_do_texto(texto, @fluxo[:largura], opcoes[:tamanho], estilo: opcoes[:estilo])
    escrever(texto, @fluxo[:esq], cima, @fluxo[:largura], **opcoes.except(:altura))
    cima - altura
  end

  def caber(texto, livre, opcoes)
    return texto if altura_do_texto(texto, @fluxo[:largura], opcoes[:tamanho], estilo: opcoes[:estilo]) <= livre

    linha = altura_do_texto('A', @fluxo[:largura], opcoes[:tamanho], estilo: opcoes[:estilo])
    reticencias(texto, @fluxo[:largura], opcoes[:tamanho], linhas: [(livre / linha).floor, 1].max)
  end

  def prova_da_acao(recomendacao, cima)
    texto = texto_da_prova(recomendacao)
    return cima if texto.blank? || cima - @fluxo[:fim] < 30

    altura = [altura_do_texto(texto, @fluxo[:largura] - 12, 7) + 20, cima - @fluxo[:fim]].min
    cartao(@fluxo[:esq], cima, @fluxo[:largura], altura, fundo: :fundo, borda: :fundo)
    escrever_pilha([[t('acoes.a_prova'), 5, { tamanho: 7, estilo: :semibold, tinta: :apoio }],
                    [texto, 15, { tamanho: 7, altura: altura - 18 }]], @fluxo[:esq] + 6, cima, @fluxo[:largura] - 12)
    cima - altura
  end

  def texto_da_prova(recomendacao)
    [recomendacao['numeros'].presence, *Array(recomendacao['conversas']).first(2).map { |prova| prova_curta(prova) }].compact.join("\n")
  end

  def mudancas_da_acao(recomendacao, cima)
    linhas = textos_das_mudancas(recomendacao)
    return cima if linhas.empty?

    topo = correr(t('acoes.o_que_mudar'), cima, tamanho: 7, estilo: :semibold, tinta: :apoio)
    linhas.drop(1).reduce(topo) { |acima, linha| correr(linha, acima - 2) }
  end

  # O título "O que mudar" e uma linha por frente preenchida (na instrução, no sistema, na equipe).
  def textos_das_mudancas(recomendacao)
    linhas = { 'instrucao' => 'acoes.na_instrucao', 'sistema' => 'acoes.no_sistema', 'equipe' => 'acoes.na_equipe' }.filter_map do |campo, chave|
      t(chave, texto: recomendacao[campo]) if recomendacao[campo].present?
    end
    linhas.empty? ? [] : [t('acoes.o_que_mudar'), *linhas]
  end

  def ganho_da_acao(ganho, cima)
    linhas = textos_do_ganho(ganho)
    return cima if linhas.empty?

    (titulo, tamanho), (conta, tamanho_da_conta) = linhas
    topo = correr(titulo, cima, tamanho: tamanho, estilo: :semibold, tinta: serie('resultado', :texto))
    correr(conta, topo - 2, tamanho: tamanho_da_conta, tinta: :apoio)
  end

  # [[texto, tamanho], ...]: o ganho com as datas dele (e, quando a conta usou o histórico completo, dito por extenso)
  # e a conta. Sem ganho, "ainda não dá para estimar", igual à tela.
  def textos_do_ganho(ganho)
    frase = frase_do_ganho(ganho)
    titulo = t('acoes.ganho', texto: frase || t('acoes.ganho_sem_conta'))
    [[titulo, 8], ([t('acoes.como_calculamos', conta: ganho['conta']), 6.5] if ganho['conta'].present?)].compact
  end

  def colunas_de_prontidao(cima, altura)
    metade = (largura - VAO) / 2.0
    ja_da, falta = colunas_da_prontidao
    coluna_de_prontidao(ja_da, [0, cima, metade], altura)
    coluna_de_prontidao(falta, [metade + VAO, cima, metade], altura)
  end

  def colunas_da_prontidao
    ja_da = recomendacoes.select { |item| item['pronto'] == 'ja_da' }.pluck('titulo')
    falta = recomendacoes.select { |item| item['pronto'] == 'falta_dado' }.map { |item| [item['titulo'], item['falta']].compact.join(' — ') }
    [{ titulo: t('acoes.ja_da'), linhas: ja_da, serie: 'resultado' }, { titulo: t('acoes.falta_dado'), linhas: falta, serie: 'tempo' }]
  end

  # Em página própria, as colunas têm a altura do texto (não a página inteira vazia).
  def altura_da_prontidao
    metade = (largura - VAO) / 2.0
    colunas_da_prontidao.map { |coluna| altura_do_texto(texto_da_prontidao(coluna), metade - 24, 7.5) }.max + 44
  end

  def texto_da_prontidao(coluna)
    coluna[:linhas].any? ? coluna[:linhas].map { |linha| "•  #{linha}" }.join("\n") : t('vazio')
  end

  # coluna = { titulo:, linhas:, serie: }; caixa = [esq, cima, largura].
  def coluna_de_prontidao(coluna, caixa, altura)
    esq, cima, largura_total = caixa
    cartao(esq, cima, largura_total, altura - 4)
    faixa(esq + 6, cima, largura_total - 12, 3, serie(coluna[:serie]))
    texto = texto_da_prontidao(coluna)
    escrever_pilha([[coluna[:titulo], 10, { tamanho: 9, estilo: :semibold, tinta: serie(coluna[:serie], :texto) }],
                    [texto, 26, { tamanho: 7.5, altura: altura - 34 }]], esq + 12, cima, largura_total - 24)
  end
end
