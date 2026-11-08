# #1431 (F1) — os blocos do PDF (título com nível, parágrafo, página) para o corte por seção (Knowledge::CortePorSecao).
# Usa as mesmas linhas e parágrafos do Processors::PdfParagrafos (incluído junto, em Processors::Pdf), só pela geometria:
# - título: parágrafo de até MAX_LINHAS_DO_TITULO linhas com a letra maior que a do corpo, ou todo fora da fonte do corpo
#   e terminando antes da margem direita (o negrito curto). O título que quebra em duas linhas, com o espaço de linha
#   normal entre elas, já é um parágrafo só e vira um título só;
# - nível: pelo tamanho da letra entre os títulos do documento, do maior (1) para o menor;
# - parágrafo que continua na página seguinte (a mesma ligação do texto) é um bloco só, com a página onde começa;
# - página de sumário sai inteira: a maioria das linhas termina no número da página ("3. FRANQUIA ........ 7").
# Rodapé corrido e número de página já saem no PdfParagrafos.
module Autonomia::Agents::Knowledge::Processors::PdfBlocos
  MAX_LINHAS_DO_TITULO = 3
  # Página de sumário: pelo menos MIN_LINHAS_DO_SUMARIO linhas, e pelo menos FRACAO_DO_SUMARIO delas terminam num número.
  MIN_LINHAS_DO_SUMARIO = 4
  FRACAO_DO_SUMARIO = 0.5

  private

  # [{ tipo: :titulo, nivel:, texto:, pagina: } | { tipo: :paragrafo, texto:, pagina: }], na ordem do documento.
  def blocos_em_paragrafos(pages)
    linhas = pages.map { |page| linhas_da_pagina(page) }
    documento = { normal: espaco_normal(linhas), fonte_do_corpo: fonte_do_corpo(linhas), letra_do_corpo: letra_do_corpo(linhas) }
    paginas = sem_rodape(pages.each_with_index.map { |page, indice| pagina_lida(page, linhas[indice], documento) })
    com_niveis(blocos_das_paginas(paginas))
  end

  def blocos_das_paginas(paginas)
    continua = false
    paginas.each_with_index.with_object([]) do |(pagina, indice), blocos|
      next continua = false if pagina[:linhas].empty? || sumario?(pagina)

      grupos(pagina).each_with_index do |grupo, posicao|
        acrescentar(blocos, bloco_do_grupo(grupo, pagina, indice + 1), continua: continua && posicao.zero?)
      end
      continua = continua?(pagina, paginas[indice + 1])
    end
  end

  # O primeiro parágrafo da página que continua o último da anterior entra nele (fica a página onde começou).
  def acrescentar(blocos, bloco, continua:)
    return blocos << bloco unless continua && blocos.last&.dig(:tipo) == :paragrafo && bloco[:tipo] == :paragrafo

    blocos[-1] = blocos.last.merge(texto: "#{blocos.last[:texto]}\n#{bloco[:texto]}")
  end

  def bloco_do_grupo(grupo, pagina, numero)
    return { tipo: :paragrafo, texto: grupo.pluck(:texto).join("\n"), pagina: numero } unless titulo?(grupo, pagina)

    { tipo: :titulo, letra: grupo.first[:letra], texto: grupo.pluck(:texto).join(' '), pagina: numero }
  end

  def titulo?(grupo, pagina)
    return false if grupo.size > MAX_LINHAS_DO_TITULO

    letra_maior?(grupo.first, pagina) ||
      (grupo.all? { |linha| linha[:fonte].exclude?(pagina[:fonte_do_corpo]) } && antes_da_margem?(grupo.last, pagina))
  end

  def letra_maior?(linha, pagina)
    linha[:letra] > pagina[:letra_do_corpo] * (1 + Autonomia::Agents::Knowledge::Processors::PdfParagrafos::TROCA_DE_LETRA)
  end

  # O nível de cada título: a posição da letra dele entre as letras de título do documento, da maior para a menor.
  def com_niveis(blocos)
    letras = blocos.select { |bloco| bloco[:tipo] == :titulo }.pluck(:letra).uniq.sort.reverse
    blocos.map do |bloco|
      next bloco unless bloco[:tipo] == :titulo

      { tipo: :titulo, nivel: letras.index(bloco[:letra]) + 1, texto: bloco[:texto], pagina: bloco[:pagina] }
    end
  end

  # A letra que cobre mais texto no documento.
  def letra_do_corpo(linhas_por_pagina)
    linhas_por_pagina.flatten.each_with_object(Hash.new(0)) { |linha, soma| soma[linha[:letra]] += linha[:texto].length }
                     .max_by(&:last)&.first.to_f
  end

  def sumario?(pagina)
    linhas = pagina[:linhas]
    com_numero = linhas.count { |linha| termina_em_numero?(linha[:texto]) }
    linhas.size >= MIN_LINHAS_DO_SUMARIO && com_numero >= linhas.size * FRACAO_DO_SUMARIO
  end

  def termina_em_numero?(texto)
    palavras = texto.split
    palavras.size > 1 && palavras.last == palavras.last.to_i.to_s
  end
end
