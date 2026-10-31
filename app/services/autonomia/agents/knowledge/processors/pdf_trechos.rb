# #1426 (#2425) — os trechos de texto da página do PDF, juntados dos caracteres, com a fonte de cada um (usado por
# Processors::PdfParagrafos).
#
# Por que existe: o `runs(merge: true)` do pdf-reader só põe espaço entre duas letras com folga acima de 20% da letra. O
# texto justificado que aperta as letras (espaçamento negativo) deixa o espaço entre palavras abaixo disso, e as palavras
# saíam coladas ("NÃOFAZERNENHUMACORDO", em cerca de 10% dos pedaços do PDF de 74 páginas da #2425). E o TextRun não traz a
# fonte, que separa o título colado ao texto.
class Autonomia::Agents::Knowledge::Processors::PdfTrechos
  # Trecho de texto (caracteres juntados) com quantos caracteres há de cada fonte.
  Trecho = Struct.new(:x, :y, :width, :font_size, :text, :fontes, keyword_init: true)

  # Espaço entre palavras: folga acima da folga comum em mais de 10% da letra. Medido nos PDFs da #2425 (folga menos a
  # folga comum, dividida pela letra): entre letras fica abaixo de 0,05, entre palavras começa em 0,15. O limite de 20%
  # do pdf-reader cortava parte dos espaços (de 0,15 a 0,2) e colava palavras.
  FOLGA_DE_PALAVRA = 0.1
  # O pdf-reader junta o caractere que começa até 3 pt antes do fim do anterior; trecho de mais de um caractere que começa
  # antes disso é sobreposto (um acento desenhado à parte, sobre a letra, é um caractere só e fica colado).
  SOBREPOSTO = 3
  # Letras expandidas (folga comum positiva) só contam até a folga com que o pdf-reader já põe espaço (20% da letra): acima
  # disso a folga comum é o próprio espaço entre palavras (números de uma tabela, "1 2 3 4").
  EXPANSAO_MAX = 0.2

  class << self
    # Os trechos de texto da página, juntados dos caracteres pela mesma regra do `runs(merge: true)` do pdf-reader (mesma
    # altura, mesma letra, o seguinte começa até 3 pt antes ou uma letra depois do fim do anterior), mas com o espaço entre
    # palavras pela folga comum do trecho (FOLGA_DE_PALAVRA).
    def da_pagina(page)
      leitor = Leitor.new
      page.walk(leitor)
      caracteres = leitor.runs(merge: false).reject { |caractere| texto_do(caractere).strip.empty? }
      caracteres.group_by { |caractere| caractere.y.to_i }.flat_map do |_, mesma_altura|
        mesma_altura.sort_by(&:x).slice_when { |anterior, caractere| !anterior.mergable?(caractere) }
                    .map { |grupo| trecho(grupo, leitor.fontes) }
      end
    end

    def juntar(trechos, aperto = 0, sobreposto: false)
      trechos.each_with_index.map do |trecho, indice|
        anterior = indice.positive? && trechos[indice - 1]
        espaco = anterior && (separa?(anterior, trecho, aperto) || (sobreposto && sobreposto?(anterior, trecho)))
        espaco ? " #{texto_do(trecho)}" : texto_do(trecho)
      end.join
    end

    def letra_do(trecho)
      trecho.font_size.to_f
    end

    def texto_do(trecho)
      trecho.text.to_s.dup.force_encoding('UTF-8').scrub('')
    end

    private

    def trecho(caracteres, fontes)
      ultimo = caracteres.last
      Trecho.new(x: caracteres.first.x, y: caracteres.first.y, width: ultimo.x + ultimo.width - caracteres.first.x,
                 font_size: ultimo.font_size, text: juntar(caracteres, aperto(caracteres)),
                 fontes: caracteres.map { |caractere| fontes[caractere] }.tally)
    end

    def separa?(anterior, trecho, aperto)
      folga(anterior, trecho) - aperto > letra_do(trecho) * FOLGA_DE_PALAVRA
    end

    def sobreposto?(anterior, trecho)
      folga(anterior, trecho) < -SOBREPOSTO && [anterior, trecho].all? { |um| texto_do(um).length > 1 }
    end

    # A folga comum entre as letras do trecho: o texto justificado que aperta as letras (no PDF de 74 páginas da #2425,
    # -0,75 pt entre letras e +1,75 pt entre palavras) ou o que as expande (Tc positivo). Com 4 folgas ou mais, o quartil de
    # baixo (as folgas entre letras são a maioria); com menos, a mediana de baixo e só negativa (num trecho de duas palavras
    # a folga positiva seria o próprio espaço entre elas). Positiva, vale só abaixo de EXPANSAO_MAX da letra.
    def aperto(caracteres)
      folgas = caracteres.each_cons(2).map { |anterior, caractere| folga(anterior, caractere) }.sort
      return 0 if folgas.empty?
      return [folgas[(folgas.size - 1) / 2], 0].min if folgas.size < 4

      comum = folgas[(folgas.size - 1) / 4]
      comum > letra_do(caracteres.first) * EXPANSAO_MAX ? 0 : comum
    end

    def folga(anterior, trecho)
      trecho.x - (anterior.x + anterior.width)
    end
  end
end
