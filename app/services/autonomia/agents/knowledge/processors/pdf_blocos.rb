# #1431 (F1) — os blocos do PDF (título com nível, parágrafo, página) para o corte por seção (Knowledge::CortePorSecao).
# Usa as mesmas linhas e parágrafos do Processors::PdfParagrafos (incluído junto, em Processors::Pdf), só pela geometria:
# - título: parágrafo de até MAX_LINHAS_DO_TITULO linhas com a letra maior que a do corpo, ou todo fora da fonte do corpo
#   e terminando antes da margem direita (o negrito curto). O título que quebra em duas linhas, com o espaço de linha
#   normal entre elas, já é um parágrafo só e vira um título só; dois títulos seguidos no mesmo parágrafo se separam
#   (`partes_do_titulo`);
# - nível: pelo tamanho da letra entre os títulos do documento, do maior (1) para o menor, e na mesma letra pela
#   numeração (Numeracao);
# - parágrafo que continua na página seguinte (a mesma ligação do texto) é um bloco só, com a página onde começa;
# - página de sumário sai inteira: a maioria das linhas termina no número da página, depois da linha de pontos
#   ("3. FRANQUIA ........ 7"). Sem a linha de pontos a página fica: perder uma tabela custa mais que guardar um sumário.
# - item: dentro do parágrafo, a linha que termina antes da margem fecha um item (o item de lista, o verbete do glossário);
#   o corte por seção faz de cada item também um trecho, para ele não sumir diluído na seção longa;
# - tabela: lida por célula no PdfTabelas;
# - a linha que se repete no alto ou no pé das páginas fica só na primeira vez, também com o número da página no fim.
# Rodapé corrido e número de página já saem no PdfParagrafos.
module Autonomia::Agents::Knowledge::Processors::PdfBlocos
  include Autonomia::Agents::Knowledge::Processors::PdfBlocos::Separacao

  MAX_LINHAS_DO_TITULO = 3
  # Página de sumário: pelo menos MIN_LINHAS_DO_SUMARIO linhas, e pelo menos FRACAO_DO_SUMARIO delas terminam num número.
  MIN_LINHAS_DO_SUMARIO = 4
  FRACAO_DO_SUMARIO = 0.5
  LINHA_DE_PONTOS = ['...', '…'].freeze

  private

  # [{ tipo: :titulo, nivel:, texto:, pagina: } | { tipo: :paragrafo, texto:, pagina: }], na ordem do documento.
  def blocos_em_paragrafos(pages)
    linhas = pages.map { |page| linhas_da_pagina(page) }
    documento = { normal: espaco_normal(linhas), fonte_do_corpo: fonte_do_corpo(linhas), letra_do_corpo: letra_do_corpo(linhas),
                  total_de_paginas: @paginas_total || pages.size }
    paginas = sem_bordas_corridas(sem_rodape(pages.each_with_index.map { |page, indice| pagina_lida(page, linhas[indice], documento) }))
    com_niveis(blocos_das_paginas(paginas))
  end

  def blocos_das_paginas(paginas)
    continua = false
    paginas.each_with_index.with_object([]) do |(pagina, indice), blocos|
      next continua = false if pagina[:linhas].empty? || sumario_fora?(pagina, indice + 1)

      blocos_da_pagina(pagina, indice + 1).each_with_index do |bloco, posicao|
        acrescentar(blocos, bloco, continua: continua && posicao.zero?)
      end
      continua = continua?(pagina, paginas[indice + 1])
    end
  end

  # Os blocos da página: cada tabela (PdfTabelas) e, no texto corrido entre elas, os títulos e os parágrafos.
  def blocos_da_pagina(pagina, numero)
    pedacos_da_pagina(pagina).flat_map do |pedaco|
      next [bloco_da_tabela(pedaco, pagina, numero)] if pedaco[:tabela]

      anterior = nil
      grupos(pagina.merge(linhas: pedaco[:linhas])).flat_map do |grupo|
        partes = fim_da_frase?(anterior, grupo.first, pagina) ? [[grupo, false]] : partes_do_titulo(grupo, pagina)
        anterior = grupo.last
        partes.map { |parte, titulo| bloco_do_grupo(parte, pagina, numero, titulo: titulo) }
      end
    end
  end

  # O primeiro parágrafo da página que continua o último da anterior entra nele: fica a página onde começou e a do fim, e
  # o último item de lá continua no primeiro item daqui.
  def acrescentar(blocos, bloco, continua:)
    return blocos << bloco unless continua && blocos.last&.dig(:tipo) == :paragrafo && bloco[:tipo] == :paragrafo

    anterior = blocos.last
    itens = [*anterior[:itens][0...-1], "#{anterior[:itens].last}\n#{bloco[:itens].first}", *bloco[:itens].drop(1)]
    blocos[-1] = anterior.merge(texto: "#{anterior[:texto]}\n#{bloco[:texto]}", itens: itens, pagina_fim: bloco[:pagina])
  end

  def bloco_do_grupo(grupo, pagina, numero, titulo:)
    unless titulo && titulo?(grupo, pagina)
      return { tipo: :paragrafo, texto: grupo.pluck(:texto).join("\n"), itens: itens_do_grupo(grupo, pagina), pagina: numero }
    end

    { tipo: :titulo, letra: grupo.first[:letra], texto: grupo.pluck(:texto).join(' '), pagina: numero }
  end

  # Os itens do parágrafo: cada um termina na linha que para antes da margem direita. No texto alinhado à esquerda quase
  # toda linha para antes dela e cada linha viraria item, cortado no meio da frase: com menos de um terço das linhas
  # chegando à margem, o parágrafo é um item só.
  def itens_do_grupo(grupo, pagina)
    return [grupo.pluck(:texto).join("\n")] if grupo.count { |linha| !antes_da_margem?(linha, pagina) } * 3 < grupo.size

    grupo.slice_after { |linha| antes_da_margem?(linha, pagina) }.map { |linhas| linhas.pluck(:texto).join("\n") }
  end

  def titulo?(grupo, pagina)
    return false if grupo.size > MAX_LINHAS_DO_TITULO

    letra_maior?(grupo.first, pagina) ||
      (grupo.all? { |linha| linha[:fonte].exclude?(pagina[:fonte_do_corpo]) } && antes_da_margem?(grupo.last, pagina))
  end

  def letra_maior?(linha, pagina)
    linha[:letra] > pagina[:letra_do_corpo] * (1 + Autonomia::Agents::Knowledge::Processors::PdfParagrafos::TROCA_DE_LETRA)
  end

  # O nível de cada título: primeiro a posição da letra dele entre as letras de título do documento, da maior para a
  # menor (letras que diferem menos que TROCA_DE_LETRA, 11,98 e 12, são a mesma); depois, na mesma letra, a numeração
  # (#2863, Numeracao). Os pares viram níveis seguidos, 1, 2, 3…
  def com_niveis(blocos)
    titulos = blocos.select { |bloco| bloco[:tipo] == :titulo }
    letras = niveis_das_letras(titulos.pluck(:letra))
    chave = ->(bloco) { [letras[bloco[:letra]], Autonomia::Agents::Knowledge::Processors::PdfBlocos::Numeracao.profundidade(bloco[:texto])] }
    niveis = titulos.map(&chave).uniq.sort.each_with_index.to_h { |par, indice| [par, indice + 1] }
    blocos.map do |bloco|
      next bloco unless bloco[:tipo] == :titulo

      { tipo: :titulo, nivel: niveis[chave.call(bloco)], texto: bloco[:texto], pagina: bloco[:pagina] }
    end
  end

  # { letra => nível }: da maior para a menor, a letra perto da anterior fica no mesmo nível.
  def niveis_das_letras(letras)
    grupos = letras.uniq.sort.reverse.slice_when do |maior, menor|
      maior - menor > maior * Autonomia::Agents::Knowledge::Processors::PdfParagrafos::TROCA_DE_LETRA
    end
    grupos.each_with_index.with_object({}) { |(grupo, indice), niveis| grupo.each { |letra| niveis[letra] = indice + 1 } }
  end

  # A letra que cobre mais texto no documento.
  def letra_do_corpo(linhas_por_pagina)
    linhas_por_pagina.flatten.each_with_object(Hash.new(0)) { |linha, soma| soma[linha[:letra]] += linha[:texto].length }
                     .max_by(&:last)&.first.to_f
  end

  # A linha que se repete no pé de pelo menos CORRIDO_FRACAO das páginas, na mesma altura, fica só na primeira vez; a do
  # alto sai sempre (o "SUMÁRIO" de volta ao índice em toda página, que deixado uma vez virava o título de tudo o que vinha
  # depois). O rodapé corrido do PdfParagrafos não pega a que traz o número da página no fim ("Condições Gerais – Versão
  # 3.0. 31"), que muda de página em página, nem a do alto, que ele não olha.
  def sem_bordas_corridas(paginas)
    return paginas if paginas.size < Autonomia::Agents::Knowledge::Processors::PdfParagrafos::CORRIDO_MIN_PAGINAS

    corridas = repetidos(paginas, paginas.map { |pagina| pagina[:linhas].each_index.filter_map { |indice| chave_da_borda(pagina, indice) } })
    vistas = Set.new
    paginas.map do |pagina|
      # O sumário é decidido uma vez, sem as linhas corridas, e vale também em blocos_das_paginas: a página de sumário
      # sai, e o pé lido nela não conta como visto.
      sumario = sumario?(pagina.merge(linhas: sem_corridas(pagina) { |chave| corridas.include?(chave) }))
      desta = sumario ? vistas.dup : vistas
      pagina.merge(linhas: sem_corridas(pagina) { |chave| sai_da_borda?(chave, corridas, desta) }, sumario: sumario)
    end
  end

  # As linhas da página sem as da borda em que o bloco diz sim.
  def sem_corridas(pagina)
    pagina[:linhas].reject.with_index { |_, indice| yield(chave_da_borda(pagina, indice)) }
  end

  def sai_da_borda?(chave, corridas, vistas)
    corridas.include?(chave) && (chave.last == :alto || !vistas.add?(chave))
  end

  # [texto, altura, :alto ou :pe] da linha na borda da folha; nil no meio da folha. No pé, sem o número da página no fim;
  # no alto, o texto inteiro ("CLÁUSULA 5" e "CLÁUSULA 6" no topo são títulos diferentes).
  def chave_da_borda(pagina, indice)
    linha = pagina[:linhas][indice]
    borda = borda(pagina, linha[:y])
    return if borda.nil?

    palavras = linha[:texto].split
    palavras = palavras[0...-1] if borda == :pe && palavras.last == palavras.last.to_i.to_s
    [palavras.join(' '), linha[:y].round, borda] if palavras.any?
  end

  def borda(pagina, altura)
    return if pagina[:folha].nil?

    baixo, tamanho = pagina[:folha]
    faixa = Autonomia::Agents::Knowledge::Processors::PdfParagrafos::FAIXA_DO_RODAPE
    relativa = (altura - baixo) / tamanho.abs
    return :pe if relativa <= faixa

    :alto if relativa >= 1 - faixa
  end

  def sumario_fora?(pagina, numero)
    return false unless pagina.fetch(:sumario) { sumario?(pagina) }

    Rails.logger.info("[autonomia][pdf_blocos] página #{numero} lida como sumário, fora do corte por seção")
    true
  end

  # Sumário: a maioria das linhas termina num número depois da linha de pontos, e esses números são páginas do documento,
  # crescendo de cima para baixo. Uma tabela de valores (percentuais, preços, prazos) também termina em número, mas sem a
  # linha de pontos, e muitas vezes os números não crescem assim. A ordem vale só nas linhas com pontos: o rodapé que
  # termina no número da página ("Processo SUSEP nº … – Versão 3.0. 2") não tem pontos e não conta.
  def sumario?(pagina)
    linhas = pagina[:linhas]
    numeradas = linhas.select { |linha| numero_no_fim(linha[:texto]) }
    com_pontos = numeradas.select { |linha| com_linha_de_pontos?(linha[:texto]) }
    linhas.size >= MIN_LINHAS_DO_SUMARIO && numeradas.size >= linhas.size * FRACAO_DO_SUMARIO &&
      com_pontos.size >= numeradas.size * FRACAO_DO_SUMARIO &&
      paginas_do_documento?(com_pontos.map { |linha| numero_no_fim(linha[:texto]) }, pagina[:total_de_paginas])
  end

  # Os números crescem de cima para baixo e nenhum passa do total de páginas.
  def paginas_do_documento?(numeros, total)
    numeros.each_cons(2).all? { |anterior, seguinte| anterior <= seguinte } && numeros.max <= total
  end

  def com_linha_de_pontos?(texto)
    LINHA_DE_PONTOS.any? { |pontos| texto.include?(pontos) }
  end

  def numero_no_fim(texto)
    palavras = texto.split
    palavras.last.to_i if palavras.size > 1 && palavras.last == palavras.last.to_i.to_s
  end
end
