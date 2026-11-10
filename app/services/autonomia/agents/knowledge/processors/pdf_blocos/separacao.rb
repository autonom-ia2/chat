# #2862, #2863, #2865 — onde o bloco de linhas do PDF se separa em título e parágrafo (incluído em Processors::PdfBlocos):
# os títulos seguidos, a linha que termina a frase de cima e os títulos depois de um parágrafo em negrito. Só geometria,
# fonte e a forma da numeração (Numeracao).
module Autonomia::Agents::Knowledge::Processors::PdfBlocos::Separacao
  private

  # #2863 — a linha que vem logo depois de uma linha que vai até a margem, com o espaço de linha normal, termina a frase de
  # cima (o endereço em negrito no fim do parágrafo): não é título, mesmo curta e em outra fonte. Sem isso, o título sem
  # número viraria pai de todas as seções seguintes.
  def fim_da_frase?(de_cima, de_baixo, pagina)
    return false if de_cima.nil? || antes_da_margem?(de_cima, pagina)

    de_cima[:y] - de_baixo[:y] <= pagina[:normal] * (1 + Autonomia::Agents::Knowledge::Processors::PdfParagrafos::TROCA_DE_LETRA)
  end

  # #2862 — o grupo lido como título pode ser dois títulos seguidos ("CLÁUSULA 2 – CONTRATAÇÃO" e "2.1. ACEITAÇÃO"): o
  # espaço entre eles fica abaixo do de parágrafo, e a fonte é a mesma. Separa onde as duas coisas valem: a linha de baixo
  # caberia inteira no fim da de cima (quem quebra por falta de espaço não deixa caber) e o espaço passa do de linha.
  # #2865 — o grupo que não é título pode terminar em títulos (titulos_no_fim) ou ter um título no meio (titulos_no_meio).
  def partes_do_titulo(grupo, pagina)
    partes = grupo.slice_when { |de_cima, de_baixo| titulos_seguidos?(de_cima, de_baixo, pagina) }.to_a
    return partes.map { |parte| [parte, true] } if titulo?(grupo, pagina)

    titulos_no_fim(partes, pagina) || titulos_no_meio(grupo, pagina) || [[grupo, false]]
  end

  # #2865 — o título no meio do bloco em negrito, logo antes de um parágrafo também em negrito ("4.4. HIPÓTESES DE PERDA"
  # e, embaixo, o "4.4.1. …" recuado): o bloco se parte onde a linha de cima para antes da margem e o espaço passa do de
  # linha (fim de parágrafo); é título a parte de uma linha só, título de seção, com o texto de baixo mais recuado que
  # ela, ou com um título filho dela pela numeração logo embaixo ("CLÁUSULA 4" e "4.1."). A lista em negrito, um item por
  # linha no mesmo recuo do texto de baixo, não muda, nem quando um título vem logo depois dela ("2." não é pai de
  # "4.5."). Sem título no meio, o bloco fica como estava.
  def titulos_no_meio(grupo, pagina)
    partes = grupo.slice_when { |de_cima, de_baixo| paragrafo_acaba?(de_cima, de_baixo, pagina) }.to_a
    marcas = marcas_de_titulo(partes, pagina)
    return unless marcas.any?

    partes.zip(marcas).slice_when { |(_, titulo), (_, seguinte)| titulo || seguinte }.map do |pedaco|
      [pedaco.flat_map(&:first), pedaco.first.last]
    end
  end

  # De baixo para cima: a última parte nunca é título (o título tem texto embaixo).
  def marcas_de_titulo(partes, pagina)
    partes.each_index.reverse_each.with_object([]) do |indice, marcas|
      seguinte = partes[indice + 1]
      titulo = !seguinte.nil? && partes[indice].size == 1 && titulo_de_secao?(partes[indice], pagina) &&
               (recuada?(seguinte.first, partes[indice].first) || (marcas.first && filho?(partes[indice], seguinte)))
      marcas.unshift(titulo)
    end
  end

  def paragrafo_acaba?(de_cima, de_baixo, pagina)
    antes_da_margem?(de_cima, pagina) &&
      de_cima[:y] - de_baixo[:y] > pagina[:normal] * (1 + Autonomia::Agents::Knowledge::Processors::PdfParagrafos::TROCA_DE_LETRA)
  end

  # A linha de baixo começa mais à direita que a de cima, por mais de uma letra.
  def recuada?(de_baixo, de_cima)
    de_baixo[:trechos].first[:x] > de_cima[:trechos].first[:x] + de_cima[:letra]
  end

  # #2865 — o parágrafo (todo em negrito, por exemplo) seguido, no mesmo bloco, de títulos com a mesma separação dos
  # títulos seguidos: o começo continua parágrafo e o que vem depois é título, se cada parte depois do começo for título,
  # não começar por marcador de item ("a)") e cada uma for filha da de cima pela numeração (Numeracao.filho?). A lista em
  # negrito, um item por linha ("a)", ou "1." e "2." irmãos), continua no parágrafo. Senão, o bloco fica como estava.
  def titulos_no_fim(partes, pagina)
    titulos = partes.drop(1)
    return if titulos.empty? || !titulos.all? { |parte| titulo_de_secao?(parte, pagina) }
    return unless titulos.each_cons(2).all? { |de_cima, de_baixo| filho?(de_cima, de_baixo) }

    [[partes.first, false], *partes.drop(1).map { |parte| [parte, true] }]
  end

  def filho?(de_cima, de_baixo)
    Autonomia::Agents::Knowledge::Processors::PdfBlocos::Numeracao.filho?(de_cima.first[:texto], de_baixo.first[:texto])
  end

  def titulo_de_secao?(parte, pagina)
    titulo?(parte, pagina) &&
      Autonomia::Agents::Knowledge::Processors::PdfBlocos::Numeracao.profundidade(parte.first[:texto]) !=
        Autonomia::Agents::Knowledge::Processors::PdfBlocos::Numeracao::ITEM
  end

  def titulos_seguidos?(de_cima, de_baixo, pagina)
    largura = de_baixo[:direita] - de_baixo[:trechos].first[:x]
    largura <= pagina[:corpo].pluck(:direita).max - de_cima[:direita] &&
      de_cima[:y] - de_baixo[:y] > pagina[:normal] * (1 + Autonomia::Agents::Knowledge::Processors::PdfParagrafos::TROCA_DE_LETRA)
  end
end
