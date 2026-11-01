# Acha uma chave forjada como a moldura da equipe acha (#1669: sem invisíveis, em NFKC, espaços unificados, sem caixa)
# e troca SÓ o trecho dela no texto original (#1775). A comparação do texto inteiro normalizado devolvia o texto
# reescrito: "m²" virava "m2", o emoji de família se partia e o cabeçalho deixava "[]" para trás.
#
# Cada caractere é normalizado sozinho e guarda o índice do caractere original de onde veio. As chaves são ASCII, e a
# NFKC do texto inteiro só compõe sequências que não viram ASCII: nada que a comparação antiga pegava escapa desta.
# Também sai da comparação o combinante (acento solto, U+0301 e afins), que a NFKC não tira e que, no meio da chave, a
# esconderia.
module Autonomia::Agents::Operate::ChaveNoOriginal
  COMBINANTES = [0x0300..0x036F, 0x1AB0..0x1AFF, 0x1DC0..0x1DFF, 0x20D0..0x20FF, 0xFE20..0xFE2F].freeze

  module_function

  def contem_alguma?(texto, chaves)
    disfarce.contem_alguma?(plano_com_origem(texto).first, chaves)
  end

  # Troca cada ocorrência de qualquer das `chaves` por `por`, a mais longa primeiro. Só o trecho original da chave muda.
  def trocar(texto, chaves, por)
    plano, origem = plano_com_origem(texto)
    ordenadas = chaves.reject(&:empty?).sort_by { |chave| -chave.length }
    saida = +''
    copiado = 0
    posicao = 0
    while posicao < plano.length
      chave = chave_em(plano, posicao, ordenadas)
      unless chave
        posicao += 1
        next
      end

      saida << texto[copiado...origem[posicao]].to_s << por
      copiado = origem[posicao + chave.length - 1] + 1
      posicao += chave.length
    end
    saida << texto[copiado..].to_s
  end

  def chave_em(plano, posicao, chaves)
    chaves.find { |chave| plano[posicao, chave.length].casecmp?(chave) }
  end

  # O texto plano (cada caractere sem invisível nem combinante, em NFKC; espaços seguidos viram um; as quebras ficam) e,
  # para cada caractere dele, o índice do caractere original de onde veio.
  def plano_com_origem(texto)
    plano = +''
    origem = []
    texto.each_char.with_index do |caractere, indice|
      forma = forma_plana(caractere)
      next if forma.empty? || (forma == ' ' && plano.end_with?(' '))

      plano << forma
      forma.length.times { origem << indice }
    end
    [plano, origem]
  end

  # O caractere como a comparação o vê: vazio se invisível ou combinante, um espaço se for espaço de qualquer tipo.
  def forma_plana(caractere)
    return '' if disfarce.formato?(caractere.ord) || combinante?(caractere.ord)

    forma = caractere.unicode_normalize(:nfkc)
    caractere != "\n" && forma.strip.empty? ? ' ' : forma
  end

  def combinante?(codepoint)
    COMBINANTES.any? { |faixa| faixa.cover?(codepoint) }
  end

  def disfarce
    ::Autonomia::Agents::Operate::TextoSemDisfarce
  end
end
