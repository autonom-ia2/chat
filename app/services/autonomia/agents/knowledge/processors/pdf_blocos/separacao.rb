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
  def partes_do_titulo(grupo, pagina)
    partes = grupo.slice_when { |de_cima, de_baixo| titulos_seguidos?(de_cima, de_baixo, pagina) }.to_a
    return partes.map { |parte| [parte, true] } if titulo?(grupo, pagina)

    titulos_no_fim(partes, pagina) || [[grupo, false]]
  end

  # #2865 — o parágrafo (todo em negrito, por exemplo) seguido, no mesmo bloco, de títulos com a mesma separação dos
  # títulos seguidos: o começo continua parágrafo e o que vem depois é título, se cada parte depois do começo for título
  # e não começar por marcador de item ("a)": a lista em negrito, um item por linha, continua no parágrafo). Senão, o
  # bloco fica inteiro como estava.
  def titulos_no_fim(partes, pagina)
    return if partes.size < 2 || !partes.drop(1).all? { |parte| titulo_de_secao?(parte, pagina) }

    [[partes.first, false], *partes.drop(1).map { |parte| [parte, true] }]
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
