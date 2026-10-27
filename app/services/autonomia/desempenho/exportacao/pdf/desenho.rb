# Peças de desenho do PDF do painel de desempenho (#2226): texto, cartão, faixa, mini-estatística, ressalva, pílula,
# e barra (o ranking fica em Ranking). O ponto (esq, cima) é o canto superior esquerdo, medido dentro da
# área útil da página (o y do Prawn cresce para cima). Cada peça devolve o `cima` logo abaixo dela.
module Autonomia::Desempenho::Exportacao::Pdf::Desenho
  RAIO = 8
  ALTURA_DA_MINI = 36
  VAO_DA_MINI = 8
  MENOR_FONTE = 6.5
  TEXTO_PADRAO = { tamanho: 9, tinta: :tinta, estilo: :normal, altura: nil, alinhar: :left, formatado: false, entrelinha: 0 }.freeze

  def cor(chave)
    Autonomia::Desempenho::Exportacao::Pdf::COR.fetch(chave)
  end

  def serie(nome, tom = :barra)
    series = Autonomia::Desempenho::Exportacao::Pdf::SERIE
    series.fetch(nome.to_s, series['neutro']).fetch(tom)
  end

  def tinta(valor)
    valor.is_a?(Symbol) ? cor(valor) : valor
  end

  # Opções: tamanho, tinta (chave de COR ou hex), estilo, altura (encolhe para caber), alinhar, formatado, entrelinha.
  def escrever(texto, esq, cima, largura, **opcoes)
    opcoes = TEXTO_PADRAO.merge(opcoes)
    @doc.fill_color tinta(opcoes[:tinta])
    @doc.text_box(texto.to_s, at: [esq, cima], width: largura, **opcoes_do_texto(opcoes))
  end

  # Vários textos do mesmo bloco: [[texto, quanto desce, opções], ...].
  def escrever_pilha(textos, esq, cima, largura)
    textos.each { |texto, desce, opcoes| escrever(texto, esq, cima - desce, largura, **opcoes.to_h) unless texto.nil? }
  end

  def altura_do_texto(texto, largura, tamanho, estilo: :normal)
    @doc.height_of(texto.to_s, width: largura, size: tamanho, style: estilo)
  end

  # Cores: fundo e borda (chave de COR ou hex); o padrão é o cartão branco com borda fina.
  def cartao(esq, cima, largura, altura, **cores)
    @doc.fill_color tinta(cores.fetch(:fundo, :branco))
    @doc.stroke_color tinta(cores.fetch(:borda, :linha))
    @doc.line_width 0.7
    @doc.fill_and_stroke_rounded_rectangle([esq, cima], largura, altura, RAIO)
    cima - altura
  end

  def faixa(esq, cima, largura, altura, cor_da_faixa)
    @doc.fill_color cor_da_faixa
    @doc.fill_rectangle([esq, cima], largura, altura)
  end

  def linha_fina(esq, dir, altura)
    @doc.stroke_color cor(:linha)
    @doc.line_width 0.5
    @doc.stroke_horizontal_line esq, dir, at: altura
  end

  # Título de bloco (11pt) com a descrição curta embaixo; devolve o `cima` onde o conteúdo começa.
  def titulo_do_bloco(texto, esq, cima, largura, descricao: nil)
    escrever(texto, esq, cima, largura, tamanho: 11, estilo: :semibold, altura: 14)
    return cima - 18 if descricao.blank?

    # A descrição usa até 2 linhas; mais que isso termina em "…".
    descricao = reticencias(descricao, largura, 7.5, linhas: 2)
    linhas = altura_do_texto(descricao, largura, 7.5) > altura_do_texto('A', largura, 7.5) + 0.5 ? 2 : 1
    escrever(descricao, esq, cima - 15, largura, tamanho: 7.5, tinta: :apoio, altura: 10 * linhas)
    cima - 19 - (10 * linhas)
  end

  # item = [valor, legenda, tinta do valor (opcional)].
  def mini(esq, cima, largura, item)
    valor, legenda, tinta_do_valor = item
    cartao(esq, cima, largura, ALTURA_DA_MINI, fundo: :fundo, borda: :fundo)
    escrever_pilha([[valor, 5, { tamanho: 13, estilo: :bold, tinta: tinta_do_valor || :tinta, altura: 16 }],
                    [legenda, 22, { tamanho: 7, tinta: :apoio, altura: 10 }]], esq + 8, cima, largura - 16)
  end

  def minis(esq, cima, largura, itens, colunas: itens.size)
    cada = (largura - (VAO_DA_MINI * (colunas - 1))) / colunas.to_f
    itens.each_with_index do |item, index|
      linha, coluna = index.divmod(colunas)
      mini(esq + (coluna * (cada + VAO_DA_MINI)), cima - (linha * (ALTURA_DA_MINI + 6)), cada, item)
    end
    cima - ((((itens.size - 1) / colunas) + 1) * (ALTURA_DA_MINI + 6))
  end

  def ressalva(texto, esq, cima, largura, tamanho: 8)
    altura = [altura_do_texto(texto, largura - 30, tamanho) + 12, 22].max
    cartao(esq, cima, largura, altura, fundo: :ressalva_fundo, borda: :ressalva_borda)
    @doc.fill_color serie('tempo', :texto)
    @doc.fill_circle [esq + 12, cima - 11], 3
    escrever(texto, esq + 22, cima - 6, largura - 30, tamanho: tamanho, altura: altura - 8)
    cima - altura
  end

  # As ressalvas da conferência de uma ou mais partes, uma embaixo da outra, perto dos números. Devolve o y de baixo.
  def ressalvas_da_conferencia(partes, esq, cima, largura, tamanho: 7.5)
    ressalvas_de(*partes).reduce(cima) { |topo, texto| ressalva(texto, esq, topo, largura, tamanho: tamanho) - 6 }
  end

  # A altura que `ressalvas_da_conferencia` vai ocupar, para quem precisa reservar o espaço antes.
  def altura_das_ressalvas(partes, largura, tamanho: 7.5)
    ressalvas_de(*partes).sum { |texto| [altura_do_texto(texto, largura - 30, tamanho) + 12, 22].max + 6 }
  end

  # Estilo: fundo e tinta (hex) e tamanho. Devolve a largura da pílula.
  def pilula(texto, esq, cima, **estilo)
    tamanho = estilo.fetch(:tamanho, 7.5)
    largura = @doc.width_of(texto.to_s, size: tamanho) + 14
    @doc.fill_color estilo[:fundo]
    @doc.fill_rounded_rectangle([esq, cima], largura, tamanho + 7, (tamanho + 7) / 2.0)
    escrever(texto, esq + 7, cima - 3.2, largura - 10, tamanho: tamanho, tinta: estilo[:tinta])
    largura
  end

  # Trilho na cor clara da série e a parte (0..1) na cor forte. Opções: serie (padrão 'neutro') e altura (padrão 7).
  def barra(esq, cima, largura, fracao, **opcoes)
    nome_da_serie = opcoes.fetch(:serie, 'neutro')
    altura = opcoes.fetch(:altura, 7)
    @doc.fill_color serie(nome_da_serie, :trilho)
    @doc.fill_rounded_rectangle([esq, cima], largura, altura, altura / 2.0)
    comprimento = largura * fracao.to_f.clamp(0, 1)
    return if comprimento < 1

    @doc.fill_color serie(nome_da_serie)
    @doc.fill_rounded_rectangle([esq, cima], [comprimento, altura].max, altura, altura / 2.0)
  end

  # O texto cortado em `linhas` linhas na largura dada, com "…" no fim. Corta palavra por palavra (sem regex).
  def reticencias(texto, largura, tamanho, linhas: 2)
    texto = texto.to_s
    limite = (altura_do_texto('A', largura, tamanho) * linhas) + 0.5
    return texto if altura_do_texto(texto, largura, tamanho) <= limite

    palavras = texto.split
    palavras.pop while palavras.size > 1 && altura_do_texto("#{palavras.join(' ')}…", largura, tamanho) > limite
    "#{palavras.join(' ')}…"
  end

  def vazio(esq, cima, largura)
    escrever(t('vazio'), esq, cima, largura, tamanho: 8, tinta: :apoio)
    cima - 14
  end

  private

  def opcoes_do_texto(opcoes)
    base = { size: opcoes[:tamanho], style: opcoes[:estilo], align: opcoes[:alinhar], inline_format: opcoes[:formatado],
             leading: opcoes[:entrelinha] }
    return base unless opcoes[:altura]

    base.merge(height: opcoes[:altura], overflow: :shrink_to_fit, min_font_size: menor_fonte(opcoes[:tamanho]))
  end

  # Encolher para caber nunca passa de 6,5 pt (abaixo disso não se lê impresso).
  def menor_fonte(tamanho)
    [tamanho - 3, MENOR_FONTE].max.clamp(..tamanho)
  end
end
