# Quando dois registros com a mesma seguradora e o mesmo número são A MESMA apólice (E4, #2897). A seguradora pode
# manter o número na renovação: o termo novo começa quando o anterior termina, e os dois ficam lado a lado na carteira
# (por isso o índice único leva o fim da vigência). Fora disso é a mesma apólice, e o que chega depois atualiza a que já
# está guardada (o fim corrigido na origem, o endosso) em vez de criar outra.
#
# A regra é uma só para quem grava (Carteira::Guardar, a apólice que chega contra o que a conta já tem) e para quem
# confere a planilha (Carteira::Trazer::ProblemasDeSeguro, duas linhas do mesmo arquivo).
# Sem começo de vigência não dá para saber que é termo novo: conta como a mesma apólice.
module Carteira::Termo
  module_function

  # uma, outra: { inicio_vigencia:, fim_vigencia: } (um Hash ou uma Carteira::Apolice).
  def mesmo?(uma, outra)
    !(depois?(uma, outra) || depois?(outra, uma))
  end

  def depois?(novo, anterior)
    comeca = novo[:inicio_vigencia]
    comeca.present? && comeca >= anterior[:fim_vigencia] && novo[:fim_vigencia] > anterior[:fim_vigencia]
  end
end
