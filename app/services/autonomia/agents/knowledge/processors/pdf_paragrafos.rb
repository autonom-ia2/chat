# #1426 — o texto da página do PDF remontado em parágrafos pela posição de cada linha na página (incluído em Processors::Pdf).
#
# Por que existe: o `page.text` do pdf-reader desenha a página numa grade de linhas e, em PDF digitado com quebra de linha
# dura (ex.: "Microsoft: Print To PDF"), põe linhas em branco falsas no meio do parágrafo. O Chunker lê linha em branco como
# fim de parágrafo e cortava a frase no meio: um PDF de 74 páginas virava 1.206 pedaços quase linha a linha, a amostra da
# conferência só via fragmentos e reprovava o material como "leitura ruim" (conta 1, PDF Suhai, 31/10).
#
# Como remonta, só pela geometria do PDF (nada de idioma, palavra ou regex):
# - as linhas são os trechos de texto na mesma altura da página, da esquerda para a direita;
# - o espaço normal entre linhas é a mediana dos espaços da página; espaço bem maior que ele, ou troca de tamanho de
#   letra (título), fecha o parágrafo ("\n\n"); o resto continua o parágrafo ("\n");
# - cabeçalho e rodapé corridos (o mesmo texto, na mesma altura, entre as primeiras ou últimas linhas de boa parte das
#   páginas) ficam só na primeira página em que aparecem: repetidos, entravam no meio do parágrafo que passa de uma página
#   para a outra. Só nas margens e nunca na primeira vez, para não tirar o título de uma tabela que se repete.
#
# Página em que a remontagem perde texto em relação ao `page.text` (texto girado, PDF esquisito) fica com o `page.text`,
# como antes. Só na Fase 2 e fora da Lia (quem decide é o Processors::Pdf).
module Autonomia::Agents::Knowledge::Processors::PdfParagrafos
  # Duas linhas na mesma altura: diferença de até metade do tamanho da letra.
  MESMA_LINHA = 0.5
  # Espaço entre linhas acima de 1,5 vez o normal da página fecha o parágrafo.
  QUEBRA_DE_PARAGRAFO = 1.5
  # Letra 10% maior ou menor que a da linha anterior é outro bloco (título).
  TROCA_DE_LETRA = 0.1
  # Entre dois trechos da mesma linha, uma folga acima de 10% do tamanho da letra é espaço entre palavras.
  FOLGA_DE_PALAVRA = 0.1
  # Cabeçalho/rodapé corrido: o mesmo texto na mesma altura, entre as MARGEM_LINHAS primeiras ou últimas linhas da página,
  # em pelo menos metade das páginas, num PDF de 4 páginas ou mais.
  CORRIDO_MIN_PAGINAS = 4
  CORRIDO_FRACAO = 0.5
  MARGEM_LINHAS = 2

  private

  # O texto de cada página, em parágrafos; a página que perde texto fica com o `page.text`.
  def textos_em_paragrafos(pages)
    linhas = pages.map { |page| linhas_da_pagina(page) }
    corridas = linhas_corridas(linhas)
    vistas = Set.new
    pages.zip(linhas).map do |page, das_linhas|
      tiradas = margens(das_linhas).select { |linha| corridas.include?(chave_corrida(linha)) && !vistas.add?(chave_corrida(linha)) }
      original = page.text.to_s
      remontado = paragrafos(das_linhas - tiradas)
      sem_perda?(remontado, original, tiradas) ? "#{remontado}\n\n" : "#{original}\n"
    end
  end

  # Linhas da página de cima para baixo: { y:, letra:, texto: }. Trechos seguidos (por altura) na mesma altura são uma linha.
  def linhas_da_pagina(page)
    trechos = page.runs(merge: true).reject { |trecho| trecho.text.strip.empty? }.sort_by { |trecho| [-trecho.y, trecho.x] }
    trechos.slice_when { |anterior, trecho| (anterior.y - trecho.y).abs > trecho.font_size * MESMA_LINHA }
           .map { |grupo| linha(grupo.sort_by(&:x)) }
  end

  def linha(trechos)
    texto = trechos.each_with_index.map do |trecho, indice|
      anterior = trechos[indice - 1]
      indice.positive? && trecho.x - (anterior.x + anterior.width) > trecho.font_size * FOLGA_DE_PALAVRA ? " #{trecho.text}" : trecho.text
    end
    { y: trechos.first.y, letra: trechos.map(&:font_size).max, texto: texto.join.strip }
  end

  def paragrafos(linhas)
    normal = espaco_normal(linhas)
    linhas.each_with_index.map do |atual, indice|
      next atual[:texto] if indice.zero?

      anterior = linhas[indice - 1]
      "#{quebra?(anterior, atual, normal) ? "\n\n" : "\n"}#{atual[:texto]}"
    end.join
  end

  # A mediana dos espaços entre linhas seguidas da página.
  def espaco_normal(linhas)
    espacos = linhas.each_cons(2).map { |de_cima, de_baixo| de_cima[:y] - de_baixo[:y] }.select(&:positive?).sort
    espacos.empty? ? 0 : espacos[espacos.size / 2]
  end

  def quebra?(anterior, atual, normal)
    anterior[:y] - atual[:y] > normal * QUEBRA_DE_PARAGRAFO ||
      (anterior[:letra] - atual[:letra]).abs > anterior[:letra] * TROCA_DE_LETRA
  end

  # Texto e altura que se repetem nas margens de boa parte das páginas: cabeçalho ou rodapé corrido.
  def linhas_corridas(linhas_por_pagina)
    return Set.new if linhas_por_pagina.size < CORRIDO_MIN_PAGINAS

    contagem = linhas_por_pagina.flat_map { |linhas| margens(linhas).map { |linha| chave_corrida(linha) }.uniq }.tally
    minimo = linhas_por_pagina.size * CORRIDO_FRACAO
    contagem.select { |_, vezes| vezes >= minimo }.keys.to_set
  end

  def margens(linhas)
    (linhas.first(MARGEM_LINHAS) + linhas.last(MARGEM_LINHAS)).uniq
  end

  def chave_corrida(linha)
    [linha[:texto], linha[:y].round]
  end

  # Medida objetiva: a remontagem guarda todo caractere visível do `page.text`, tirando o cabeçalho/rodapé corrido.
  def sem_perda?(remontado, original, tiradas)
    tirado = tiradas.sum { |linha| visiveis(linha[:texto]) }
    visiveis(remontado).positive? && visiveis(remontado) + tirado >= visiveis(original)
  end

  def visiveis(texto)
    texto.to_s.count("^ \t\r\n\f")
  end
end
