# #1426 (#2425) — o texto da página do PDF remontado em parágrafos pela posição de cada linha na página (incluído em
# Processors::Pdf).
#
# Por que existe: o `page.text` do pdf-reader desenha a página numa grade de linhas e, em PDF digitado com quebra de linha
# dura (ex.: "Microsoft: Print To PDF"), põe linhas em branco falsas no meio do parágrafo. O Chunker lê linha em branco como
# fim de parágrafo e cortava a frase no meio: um PDF digitado de 74 páginas virava 1.206 pedaços quase linha a linha, a
# amostra da conferência só via fragmentos e reprovava o material como "leitura ruim".
#
# Como remonta, só pela geometria do PDF (nada de idioma, palavra ou regex), com os mesmos trechos que o `page.text` usa
# (no pdf-reader 2.16, Page#text é o PageLayout sobre `runs`), juntados aqui dos caracteres:
# - as linhas são os trechos de texto na mesma altura da página, da esquerda para a direita; o espaço entre palavras é a
#   folga bem acima da folga comum entre as letras do trecho (texto justificado aperta as letras e o `page.text` colava as
#   palavras: "NÃOFAZERNENHUMACORDO");
# - o espaço normal entre linhas é a mediana (de baixo) dos espaços da página; espaço bem maior que ele, troca do
#   tamanho de letra da linha, ou linha de título (a mesma regra do Chunker), fecha o parágrafo ("\n\n"); o resto
#   continua o parágrafo ("\n"). Sem a regra de título, o título colado ao texto entrava no parágrafo e deixava de ser
#   título para o Chunker (116 títulos distintos na main viravam 58 no PDF de 74 páginas da #2425);
# - a virada de página continua o parágrafo só quando o corpo da página (sem o bloco do pé) chega ao último quarto da
#   folha e a letra segue a mesma. A geometria não distingue "frase cortada" de "parágrafo novo no topo da
#   página seguinte"; nesse caso os dois ficam no mesmo parágrafo, e o Chunker ainda corta por tamanho;
# - no pé da página (bloco de até MARGEM_LINHAS linhas separado do corpo por espaço de parágrafo):
#   - o rodapé corrido (mesmo texto, mesma altura em boa parte das páginas, nos 10% de baixo da folha) fica só na
#     primeira página;
#   - o número da página sai: a linha cujo texto é o número daquela página (o índice mais um deslocamento que vale para
#     o documento todo). Preço, total ou outra linha curta do pé ficam;
# - o topo da página não é mexido: ali pode estar o cabeçalho de uma tabela ou o título de uma seção.
# Número de página colado ao texto ou no topo fica no texto, como no `page.text`.
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
  # Entre dois caracteres ou trechos da mesma linha, uma folga 10% da letra acima da folga comum é espaço entre palavras.
  FOLGA_DE_PALAVRA = 0.1
  # O pdf-reader junta o caractere que começa até 3 pt antes do fim do anterior; trecho que começa antes disso é sobreposto.
  SOBREPOSTO = 3
  # Rodapé corrido e número de página: valem num PDF de 4 páginas ou mais, quando aparecem em pelo menos metade delas.
  CORRIDO_MIN_PAGINAS = 4
  CORRIDO_FRACAO = 0.5
  MARGEM_LINHAS = 2
  # A virada de página só continua o parágrafo quando o texto da página chega ao último quarto da folha.
  PE_DA_FOLHA = 0.25
  # Rodapé corrido só nos 10% de baixo da folha: uma linha de conteúdo repetida mais acima (preço igual em todo item) fica.
  FAIXA_DO_RODAPE = 0.1

  private

  # O texto de cada página, em parágrafos, terminando com a ligação à página seguinte ("\n" continua, "\n\n" fecha).
  def textos_em_paragrafos(pages)
    paginas = sem_rodape(pages.map { |page| pagina_lida(page) })
    pages.each_with_index.map do |page, indice|
      atual = paginas[indice]
      next "#{page.text}\n" if atual[:linhas].empty?

      "#{paragrafos(atual)}#{continua?(atual, paginas[indice + 1]) ? "\n" : "\n\n"}"
    end
  end

  # A página lida: as linhas, o espaço normal entre elas, o bloco do pé (índices) e o corpo (as linhas fora do pé).
  def pagina_lida(page)
    linhas = linhas_da_pagina(page)
    pagina = { linhas: linhas, normal: espaco_normal(linhas), folha: linhas.empty? ? nil : folha(page) }
    pe = pe(pagina)
    pagina.merge(pe: pe, corpo: linhas.reject.with_index { |_, indice| pe.include?(indice) })
  end

  # [baixo, altura] da folha, já girada pelo pdf-reader (/Rotate), como os trechos. Folha ilegível: nil, e nada que dependa
  # dela acontece (não continua o parágrafo, não tira rodapé); o `page.text` da main lê a mesma caixa e trata do erro.
  def folha(page)
    caixa = page.rectangles[:MediaBox]
    [caixa.bottom_left.y, caixa.height]
  rescue PDF::Reader::MalformedPDFError
    nil
  end

  # Linhas da página de cima para baixo: { y:, letra:, titulo:, texto: }. Trechos seguidos (por altura) na mesma altura são
  # uma linha.
  def linhas_da_pagina(page)
    trechos = trechos_da_pagina(page).sort_by { |trecho| [-trecho.y, trecho.x] }
    trechos.slice_when { |anterior, trecho| (anterior.y - trecho.y).abs > letra_do(trecho) * MESMA_LINHA }
           .map { |grupo| linha(grupo.sort_by(&:x)) }
  end

  # Os trechos de texto da página, juntados dos caracteres pela mesma regra do `runs(merge: true)` do pdf-reader (mesma
  # altura, mesma letra, o seguinte começa até 3 pt antes ou uma letra depois do fim do anterior), mas com o espaço entre
  # palavras pela folga comum do trecho: a junção do pdf-reader só põe espaço com folga acima de 20% da letra, e o texto
  # justificado que aperta as letras colava as palavras.
  def trechos_da_pagina(page)
    caracteres = page.runs(merge: false).reject { |caractere| texto_do(caractere).strip.empty? }
    caracteres.group_by { |caractere| caractere.y.to_i }.flat_map do |_, mesma_altura|
      mesma_altura.sort_by(&:x).slice_when { |anterior, caractere| !anterior.mergable?(caractere) }.map { |grupo| trecho(grupo) }
    end
  end

  def trecho(caracteres)
    ultimo = caracteres.last
    PDF::Reader::TextRun.new(caracteres.first.x, caracteres.first.y, ultimo.x + ultimo.width - caracteres.first.x,
                             ultimo.font_size, juntar(caracteres, aperto(caracteres)))
  end

  # Entre trechos, folga negativa além do que o pdf-reader junta (3 pt) é texto sobreposto (duas linhas da mesma célula na
  # mesma altura): palavras diferentes, separadas por espaço.
  def linha(trechos)
    texto = juntar(trechos, 0, sobreposto: true).strip
    { y: trechos.first.y, letra: letra_da_linha(trechos), texto: texto, titulo: Autonomia::Agents::Knowledge::Chunker.titulo?(texto) }
  end

  def juntar(trechos, aperto, sobreposto: false)
    trechos.each_with_index.map do |trecho, indice|
      anterior = indice.positive? && trechos[indice - 1]
      espaco = anterior && (separa?(anterior, trecho, aperto) || (sobreposto && folga(anterior, trecho) < -SOBREPOSTO))
      espaco ? " #{texto_do(trecho)}" : texto_do(trecho)
    end.join
  end

  # Espaço entre palavras: a folga passa a folga comum (o aperto) em mais de FOLGA_DE_PALAVRA da letra.
  def separa?(anterior, trecho, aperto)
    folga(anterior, trecho) - aperto > letra_do(trecho) * FOLGA_DE_PALAVRA
  end

  # A folga comum entre as letras do trecho (a mediana de baixo), só quando negativa: o texto justificado que aperta as
  # letras (no PDF de 74 páginas da #2425, -0,75 pt entre letras e +1,75 pt entre palavras). Folga positiva não conta: num
  # trecho de duas palavras a mediana seria o próprio espaço entre elas.
  def aperto(caracteres)
    folgas = caracteres.each_cons(2).map { |anterior, caractere| folga(anterior, caractere) }.sort
    folgas.empty? ? 0 : [folgas[(folgas.size - 1) / 2], 0].min
  end

  def folga(anterior, trecho)
    trecho.x - (anterior.x + anterior.width)
  end

  # A letra da linha é a que cobre mais texto nela: uma palavra maior no meio não faz da linha um título.
  def letra_da_linha(trechos)
    trechos.group_by { |trecho| letra_do(trecho) }.max_by { |_, mesmos| mesmos.sum { |trecho| texto_do(trecho).length } }.first
  end

  def letra_do(trecho)
    trecho.font_size.to_f
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

  # Fecha o parágrafo: espaço de parágrafo, troca de letra, ou linha de título antes ou depois (pela mesma regra de título
  # do Chunker, que só reconhece o título quando ele está num bloco próprio).
  def quebra?(anterior, atual, normal)
    separado?(anterior, atual, normal) || (anterior[:letra] - atual[:letra]).abs > anterior[:letra] * TROCA_DE_LETRA ||
      anterior[:titulo] || atual[:titulo]
  end

  def separado?(de_cima, de_baixo, normal)
    de_cima[:y] - de_baixo[:y] > normal * QUEBRA_DE_PARAGRAFO
  end

  # Liga à página seguinte quando o corpo desta (sem o bloco do pé: rodapé, número, preço) chega ao pé da folha e a letra
  # segue. A última linha pode abrir parágrafo: o termo no fim da página continua na definição da página seguinte.
  def continua?(atual, seguinte)
    return false if seguinte.nil? || seguinte[:linhas].empty?

    # Conteúdo que ficou no pé (preço, total) depois de sair rodapé e número fecha o parágrafo da página.
    ultima = atual[:corpo].last
    return false if ultima.nil? || !atual[:linhas].last.equal?(ultima)

    na_faixa?(atual, ultima[:y], PE_DA_FOLHA) && (ultima[:letra] - seguinte[:linhas].first[:letra]).abs <= ultima[:letra] * TROCA_DE_LETRA
  end

  # A altura está na faixa de baixo da folha (fração da altura, contando de baixo).
  def na_faixa?(pagina, altura, fracao)
    return false if pagina[:folha].nil?

    baixo, tamanho = pagina[:folha]
    altura - baixo <= tamanho.abs * fracao
  end

  # Tira do pé de cada página o rodapé corrido (depois da primeira vez) e o número da página.
  def sem_rodape(paginas)
    return paginas if paginas.size < CORRIDO_MIN_PAGINAS

    contexto = { corridos: corridos(paginas), deslocamento: deslocamento_da_numeracao(paginas), vistos: Set.new }
    paginas.each_with_index.map do |pagina, numero|
      tirar = pagina[:pe].select { |indice| tirar_do_pe?(pagina, indice, numero, contexto) }
      pagina.merge(linhas: pagina[:linhas].reject.with_index { |_, indice| tirar.include?(indice) })
    end
  end

  # Rodapé corrido sai depois da primeira vez (`vistos` guarda os já vistos); o número da página sai sempre.
  def tirar_do_pe?(pagina, indice, numero, contexto)
    return !contexto[:vistos].add?(chave(pagina, indice)) if contexto[:corridos].include?(chave(pagina, indice))

    !contexto[:deslocamento].nil? && pagina[:linhas][indice][:texto] == (numero + contexto[:deslocamento]).to_s
  end

  # Mesmo texto na mesma altura, no pé (na faixa do rodapé) de pelo menos CORRIDO_FRACAO das páginas.
  def corridos(paginas)
    repetidos(paginas, paginas.map do |pagina|
      pagina[:pe].select { |indice| na_faixa?(pagina, pagina[:linhas][indice][:y], FAIXA_DO_RODAPE) }.map { |indice| chave(pagina, indice) }
    end)
  end

  # Quanto somar ao índice da página para ter o número impresso nela ("6" na 6ª página: 1). Vale quando o mesmo
  # deslocamento aparece no pé de pelo menos CORRIDO_FRACAO das páginas; senão, nil (nada sai como número).
  def deslocamento_da_numeracao(paginas)
    por_pagina = paginas.each_with_index.map do |pagina, numero|
      pagina[:pe].filter_map do |indice|
        texto = pagina[:linhas][indice][:texto]
        texto.to_i - numero if texto == texto.to_i.to_s
      end
    end
    repetidos(paginas, por_pagina).first
  end

  def repetidos(paginas, valores_por_pagina)
    contagem = valores_por_pagina.flat_map(&:uniq).tally
    contagem.select { |_, vezes| vezes >= paginas.size * CORRIDO_FRACAO }.keys.to_set
  end

  def chave(pagina, indice)
    linha = pagina[:linhas][indice]
    [linha[:texto], linha[:y].round]
  end

  # Os índices do bloco do pé da página (até MARGEM_LINHAS linhas), quando ele é separado do corpo por espaço de parágrafo.
  def pe(pagina)
    linhas = pagina[:linhas]
    return [] if linhas.size <= MARGEM_LINHAS

    tamanho = (1..MARGEM_LINHAS).find { |n| separado?(linhas[-n - 1], linhas[-n], pagina[:normal]) }
    tamanho ? ((linhas.size - tamanho)...linhas.size).to_a : []
  end
end
