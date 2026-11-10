# #1426 (#2425) — a letra e as fontes de uma linha do PDF, lidas dos trechos dela (incluído em Processors::PdfParagrafos).
# #2845 — separado do PdfParagrafos junto com a fonte principal da linha.
module Autonomia::Agents::Knowledge::Processors::PdfParagrafos::FontesDaLinha
  private

  # A letra da linha é a que cobre mais texto nela: uma palavra maior no meio não faz da linha um título.
  def letra_da_linha(trechos)
    trechos.group_by { |trecho| letra_do(trecho) }.max_by { |_, mesmos| mesmos.sum { |trecho| texto_do(trecho).length } }.first
  end

  # As fontes da linha: a que cobre mais caracteres em cada trecho (o acento ou a pontuação noutra fonte não conta).
  def fonte_da_linha(trechos)
    trechos.to_set { |trecho| trecho.fontes.max_by(&:last).first }
  end

  # #2845 — a fonte que cobre mais caracteres na linha inteira. O número do item em negrito no começo da linha de texto
  # comum ("1.3.1. As condições…") não a torna uma linha em negrito (ver `titulo_sobre_o_texto?`).
  def fonte_principal(trechos)
    trechos.each_with_object(Hash.new(0)) { |trecho, soma| trecho.fontes.each { |fonte, vezes| soma[fonte] += vezes } }.max_by(&:last)&.first
  end
end
