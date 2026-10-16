# Comparação de texto à prova de disfarce (#1669), sem regex: o que a moldura da equipe usa para achar a própria marca
# e as chaves dela no texto do cliente e na resposta da IA, mesmo com outra caixa, espaço duplo, NBSP, letra que muda de
# tamanho ao mudar de caixa ("İ") ou caractere invisível de formato no meio (U+200B e os demais da categoria Cf).
#
# A comparação é em JANELAS com `casecmp?` sobre o próprio texto: nada de `downcase.index` + corte no original, que sai
# do lugar quando a minúscula tem outro tamanho.
module Autonomia::Agents::Operate::TextoSemDisfarce
  # Os codepoints invisíveis removidos antes de comparar, por faixa: a categoria Unicode Cf (formato, tabela Unicode 15)
  # e os invisíveis de fora dela listados no fim.
  FAIXAS_DE_FORMATO = [
    0x00AD..0x00AD, 0x0600..0x0605, 0x061C..0x061C, 0x06DD..0x06DD, 0x070F..0x070F, 0x0890..0x0891, 0x08E2..0x08E2,
    0x180E..0x180E, 0x200B..0x200F, 0x202A..0x202E, 0x2060..0x2064, 0x2066..0x206F, 0xFEFF..0xFEFF, 0xFFF9..0xFFFB,
    0x110BD..0x110BD, 0x110CD..0x110CD, 0x13430..0x1343F, 0x1BCA0..0x1BCA3, 0x1D173..0x1D17A, 0xE0001..0xE0001,
    0xE0020..0xE007F,
    # Invisíveis que não são Cf mas passam por letra ou espaço vazio: seletores de variação, o combinante que não junta
    # (U+034F) e os preenchimentos do Hangul (U+115F, U+1160, U+3164, U+FFA0).
    0x034F..0x034F, 0x115F..0x1160, 0x3164..0x3164, 0xFFA0..0xFFA0, 0xFE00..0xFE0F, 0xE0100..0xE01EF
  ].freeze

  module_function

  def formato?(codepoint)
    FAIXAS_DE_FORMATO.any? { |faixa| faixa.cover?(codepoint) }
  end

  # Sem os invisíveis de formato, em NFKC e com os espaços de cada linha unificados. As quebras de linha ficam.
  def normalizado(texto)
    visivel = texto.each_char.reject { |caractere| formato?(caractere.ord) }.join
    visivel.unicode_normalize(:nfkc).split("\n", -1).map { |linha| linha.split.join(' ') }.join("\n")
  end

  def contem?(texto, chave)
    return false if chave.empty? || texto.length < chave.length

    (0..(texto.length - chave.length)).any? { |inicio| texto[inicio, chave.length].casecmp?(chave) }
  end

  # A posição da primeira ocorrência da `chave` a partir de `desde`, sem diferenciar caixa, ou nil.
  def posicao(texto, chave, desde = 0)
    return if chave.empty?

    (desde..(texto.length - chave.length)).find { |inicio| texto[inicio, chave.length].casecmp?(chave) }
  end

  def contem_alguma?(texto, chaves)
    chaves.any? { |chave| contem?(texto, chave) }
  end

  # Troca cada ocorrência de qualquer das `chaves` (sem diferenciar caixa) por `por`. A mais longa primeiro, para a marca
  # inteira não ser trocada aos pedaços.
  def trocar(texto, chaves, por)
    ordenadas = chaves.reject(&:empty?).sort_by { |chave| -chave.length }
    saida = +''
    posicao = 0
    while posicao < texto.length
      chave = ordenadas.find { |candidata| texto[posicao, candidata.length].casecmp?(candidata) }
      saida << (chave ? por : texto[posicao])
      posicao += chave ? chave.length : 1
    end
    saida
  end
end
