# A ORDEM dos planos no comparativo (#3211), em funções puras:
# - `por_preco`: do mais barato ao mais caro (a capa, o resumo e os cartões seguem esta ordem); sem preço vai por
#   último; empate fica na ordem da Universal;
# - `com_recomendada_ate`: a recomendada sempre na 1ª folha de comparação. Se pela ordem do preço ela cairia depois
#   das vagas da 1ª folha, ela ocupa a última vaga dessa folha e o resto segue a ordem do preço.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Ordem
  module_function

  def por_preco(planos)
    planos.each_with_index.sort_by { |plano, indice| [preco(plano), indice] }.map(&:first)
  end

  # `itens` na ordem do preço; `indice` = a posição da recomendada neles (nil sem recomendada); `vagas` = quantos
  # cabem na 1ª folha. -> os itens na ordem dos cartões.
  def com_recomendada_ate(itens, indice, vagas)
    return itens if indice.nil? || indice < vagas

    resto = itens.reject.with_index { |_, posicao| posicao == indice }
    resto.first(vagas - 1) + [itens[indice]] + resto.drop(vagas - 1)
  end

  def preco(plano)
    plano['preco_total'].blank? ? Float::INFINITY : BigDecimal(plano['preco_total'].to_s)
  end

  private_class_method :preco
end
