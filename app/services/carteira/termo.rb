# Quando dois registros com a mesma seguradora e o mesmo número são A MESMA apólice (E4, #2897). A seguradora pode
# manter o número na renovação, e os termos ficam lado a lado na carteira (por isso o índice único leva o fim da
# vigência).
#
# É a mesma apólice só quando o começo da vigência é exatamente igual ou o fim é exatamente igual: é o fim corrigido na
# origem, ou o começo corrigido. Todo o resto é OUTRO termo, inclusive a renovação antecipada e a vigência que passa por
# cima da guardada com começo e fim diferentes. Duplicar aparece na tela e se conserta; sobrescrever o termo errado
# destrói em silêncio. Sem começo de vigência, só o fim igual diz que é a mesma.
#
# `escolher` diz qual dos termos guardados é o dos dados que chegam, para quem grava (Carteira::Guardar).
module Carteira::Termo
  AMBIGUO = :ambiguo

  module_function

  # uma, outra: { inicio_vigencia:, fim_vigencia: } (um Hash ou uma Carteira::Apolice).
  def mesmo?(uma, outra)
    mesmo_comeco?(uma, outra) || uma[:fim_vigencia] == outra[:fim_vigencia]
  end

  def mesmo_comeco?(uma, outra)
    uma[:inicio_vigencia].present? && uma[:inicio_vigencia] == outra[:inicio_vigencia]
  end

  # guardados: os registros com a mesma seguradora e o mesmo número. Devolve o que é a mesma apólice dos dados, nil
  # quando os dados são um termo novo, ou AMBIGUO quando não dá para saber qual é sem adivinhar.
  # Com mais de um candidato: vale o igual em tudo; senão, o de mesmo começo; sobrando mais de um, é ambíguo.
  def escolher(guardados, dados)
    mesmos = guardados.select { |guardado| mesmo?(guardado, dados) }
    return mesmos.first if mesmos.size <= 1

    do_comeco = mesmos.select { |guardado| mesmo_comeco?(guardado, dados) }
    identico = do_comeco.find { |guardado| guardado[:fim_vigencia] == dados[:fim_vigencia] }
    identico || (do_comeco.size == 1 ? do_comeco.first : AMBIGUO)
  end
end
