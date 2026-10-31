# #1426 (#2425) — o texto da página do PDF remontado em parágrafos pela posição de cada linha na página (incluído em
# Processors::Pdf).
#
# Por que existe: o `page.text` do pdf-reader desenha a página numa grade de linhas e, em PDF digitado com quebra de linha
# dura (ex.: "Microsoft: Print To PDF"), põe linhas em branco falsas no meio do parágrafo. O Chunker lê linha em branco como
# fim de parágrafo e cortava a frase no meio: um PDF digitado de 74 páginas virava 1.206 pedaços quase linha a linha, a
# amostra da conferência só via fragmentos e reprovava o material como "leitura ruim".
#
# Como remonta, só pela geometria do PDF (nada de idioma, palavra ou regex), com os mesmos trechos que o `page.text` usa:
# - as linhas são os trechos de texto na mesma altura da página, da esquerda para a direita;
# - o espaço normal entre linhas é a mediana (de baixo) dos espaços da página; espaço bem maior que ele, ou troca do
#   tamanho de letra da linha (título), fecha o parágrafo ("\n\n"); o resto continua o parágrafo ("\n");
# - a virada de página continua o parágrafo quando a página anterior vai até o pé do texto e a letra é a mesma;
# - cabeçalho e rodapé corridos ficam só na primeira página em que aparecem. Corrido é o bloco de até MARGEM_LINHAS linhas
#   no topo ou no pé da página, separado do corpo por espaço de parágrafo, que se repete (mesmo texto, mesma altura) em
#   boa parte das páginas. O cabeçalho de uma tabela, colado nas linhas dela, não é separado do corpo e fica em toda página.
#   No pé, a linha curta que muda a cada página na mesma altura (o número da página) sai de todas: ficando, ela entrava no
#   meio do parágrafo que passa de uma página para a outra. No topo, nunca: ali pode ser o título de uma seção.
#
# Página sem trecho de texto (escaneada) fica com o `page.text`, e o OCR segue como antes. Colunas e texto girado saem na
# mesma ordem do `page.text`: a remontagem não melhora nem piora esses casos.
module Autonomia::Agents::Knowledge::Processors::PdfParagrafos
  # Duas linhas na mesma altura: diferença de até metade do tamanho da letra.
  MESMA_LINHA = 0.5
  # Espaço entre linhas acima de 1,5 vez o normal da página fecha o parágrafo.
  QUEBRA_DE_PARAGRAFO = 1.5
  # Letra 10% maior ou menor que a da linha anterior é outro bloco (título).
  TROCA_DE_LETRA = 0.1
  # Entre dois trechos da mesma linha, uma folga acima de 10% do tamanho da letra é espaço entre palavras.
  FOLGA_DE_PALAVRA = 0.1
  # Cabeçalho/rodapé corrido: bloco de até MARGEM_LINHAS linhas, repetido em pelo menos metade das páginas, num PDF de 4
  # páginas ou mais.
  CORRIDO_MIN_PAGINAS = 4
  CORRIDO_FRACAO = 0.5
  MARGEM_LINHAS = 2
  # Número de página: linha do pé com até PE_CURTO caracteres visíveis.
  PE_CURTO = 20
  # A virada de página continua o parágrafo quando a última linha da página fica a até 2 linhas do pé do texto.
  PE_DO_TEXTO_LINHAS = 2

  private

  # O texto de cada página, em parágrafos, terminando com a ligação à página seguinte ("\n" continua, "\n\n" fecha).
  def textos_em_paragrafos(pages)
    paginas = sem_corridas(pages.map { |page| pagina_lida(page) })
    pe_do_texto = pe_do_texto(paginas)
    pages.each_with_index.map do |page, indice|
      atual = paginas[indice]
      next "#{page.text}\n" if atual[:linhas].empty?

      "#{paragrafos(atual)}#{continua?(atual, paginas[indice + 1], pe_do_texto) ? "\n" : "\n\n"}"
    end
  end

  def pagina_lida(page)
    linhas = linhas_da_pagina(page)
    { linhas: linhas, normal: espaco_normal(linhas) }
  end

  # Linhas da página de cima para baixo: { y:, letra:, texto: }. Trechos seguidos (por altura) na mesma altura são uma linha.
  def linhas_da_pagina(page)
    trechos = page.runs(merge: true).reject { |trecho| texto_do(trecho).strip.empty? }.sort_by { |trecho| [-trecho.y, trecho.x] }
    trechos.slice_when { |anterior, trecho| (anterior.y - trecho.y).abs > trecho.font_size * MESMA_LINHA }
           .map { |grupo| linha(grupo.sort_by(&:x)) }
  end

  def linha(trechos)
    texto = trechos.each_with_index.map do |trecho, indice|
      indice.positive? && separa?(trechos[indice - 1], trecho) ? " #{texto_do(trecho)}" : texto_do(trecho)
    end
    { y: trechos.first.y, letra: letra_da_linha(trechos), texto: texto.join.strip }
  end

  def separa?(anterior, trecho)
    trecho.x - (anterior.x + anterior.width) > trecho.font_size * FOLGA_DE_PALAVRA
  end

  # A letra da linha é a que cobre mais texto nela: uma palavra maior no meio não faz da linha um título.
  def letra_da_linha(trechos)
    trechos.group_by(&:font_size).max_by { |_, mesmos| mesmos.sum { |trecho| texto_do(trecho).length } }.first
  end

  def texto_do(trecho)
    trecho.text.to_s.dup.force_encoding('UTF-8').scrub('')
  end

  def paragrafos(pagina)
    linhas = pagina[:linhas]
    linhas.each_with_index.map do |atual, indice|
      next atual[:texto] if indice.zero?

      "#{quebra?(linhas[indice - 1], atual, pagina[:normal]) ? "\n\n" : "\n"}#{atual[:texto]}"
    end.join
  end

  # A mediana de baixo dos espaços entre linhas seguidas: com poucos espaços, o de parágrafo não vira o normal.
  def espaco_normal(linhas)
    espacos = linhas.each_cons(2).map { |de_cima, de_baixo| de_cima[:y] - de_baixo[:y] }.select(&:positive?).sort
    espacos.empty? ? 0 : espacos[(espacos.size - 1) / 2]
  end

  def quebra?(anterior, atual, normal)
    anterior[:y] - atual[:y] > normal * QUEBRA_DE_PARAGRAFO ||
      (anterior[:letra] - atual[:letra]).abs > anterior[:letra] * TROCA_DE_LETRA
  end

  # Liga à página seguinte quando esta vai até o pé do texto e a letra segue a mesma.
  def continua?(atual, seguinte, pe_do_texto)
    return false if seguinte.nil? || seguinte[:linhas].empty? || pe_do_texto.nil?

    ultima = atual[:linhas].last
    primeira = seguinte[:linhas].first
    ultima[:y] <= pe_do_texto + (atual[:normal] * PE_DO_TEXTO_LINHAS) &&
      (ultima[:letra] - primeira[:letra]).abs <= ultima[:letra] * TROCA_DE_LETRA
  end

  # Onde o texto costuma terminar: a mediana (de baixo) da última linha de cada página, já sem o rodapé corrido.
  def pe_do_texto(paginas)
    finais = paginas.filter_map { |pagina| pagina[:linhas].last&.dig(:y) }.sort
    finais[(finais.size - 1) / 2] unless finais.empty?
  end

  # Tira o cabeçalho/rodapé corrido das páginas depois da primeira em que ele aparece, e o número da página de todas (pelo
  # índice da linha na página).
  def sem_corridas(paginas)
    return paginas if paginas.size < CORRIDO_MIN_PAGINAS

    corridas = repetidas(paginas) { |pagina| margens(pagina).map { |indice| chave(pagina, indice) } }
    alturas = repetidas(paginas) { |pagina| pe(pagina).map { |indice| pagina[:linhas][indice][:y].round } }
    vistas = Set.new
    paginas.map do |pagina|
      tirar = margens(pagina).select { |indice| tirar?(pagina, indice, corridas, alturas, vistas) }
      pagina.merge(linhas: pagina[:linhas].reject.with_index { |_, indice| tirar.include?(indice) })
    end
  end

  # Corrida: sai depois da primeira vez (`vistas` guarda as já vistas). Senão, sai se for o número da página.
  def tirar?(pagina, indice, corridas, alturas, vistas)
    return !vistas.add?(chave(pagina, indice)) if corridas.include?(chave(pagina, indice))

    numero_da_pagina?(pagina, indice, alturas)
  end

  # Linha curta do pé, numa altura em que quase toda página tem uma linha, com texto que muda: o número da página.
  def numero_da_pagina?(pagina, indice, alturas)
    linha = pagina[:linhas][indice]
    pe(pagina).include?(indice) && alturas.include?(linha[:y].round) && linha[:texto].length <= PE_CURTO
  end

  # O que se repete em pelo menos CORRIDO_FRACAO das páginas.
  def repetidas(paginas, &)
    contagem = paginas.flat_map { |pagina| yield(pagina).uniq }.tally
    contagem.select { |_, vezes| vezes >= paginas.size * CORRIDO_FRACAO }.keys.to_set
  end

  def chave(pagina, indice)
    linha = pagina[:linhas][indice]
    [linha[:texto], linha[:y].round]
  end

  def margens(pagina)
    topo(pagina) + pe(pagina)
  end

  # Os índices do bloco do topo / do pé da página, quando ele é separado do corpo por espaço de parágrafo.
  def topo(pagina)
    linhas = pagina[:linhas]
    return [] if linhas.size <= MARGEM_LINHAS * 2

    tamanho = (1..MARGEM_LINHAS).find { |n| separado?(linhas[n - 1], linhas[n], pagina[:normal]) }
    tamanho ? (0...tamanho).to_a : []
  end

  def pe(pagina)
    linhas = pagina[:linhas]
    return [] if linhas.size <= MARGEM_LINHAS * 2

    tamanho = (1..MARGEM_LINHAS).find { |n| separado?(linhas[-n - 1], linhas[-n], pagina[:normal]) }
    tamanho ? ((linhas.size - tamanho)...linhas.size).to_a : []
  end

  def separado?(de_cima, de_baixo, normal)
    de_cima[:y] - de_baixo[:y] > normal * QUEBRA_DE_PARAGRAFO
  end
end
