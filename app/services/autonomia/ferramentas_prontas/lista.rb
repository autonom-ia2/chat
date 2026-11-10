# AS LISTAS QUE VÃO AO MODELO (#2858): marcas da FIPE, modelos de uma marca, cidades de um estado. A contagem vai antes
# da lista (se o corte do turno pegar o fim, o modelo ainda sabe quantos eram) e a lista tem teto. A busca é local, sobre
# a lista inteira da fonte (ou do cache): todas as palavras no nome, sem acento e sem caixa.
module Autonomia::FerramentasProntas::Lista
  module_function

  # O nome sem acento, sem caixa e sem espaço sobrando, para comparar nome com nome ("São Paulo" e "SAO PAULO").
  def comparavel(texto)
    I18n.transliterate(texto.to_s).downcase.squish
  end

  def cortar(itens, chave, maximo)
    { 'total' => itens.size }.merge(itens.size > maximo ? { 'mostrando' => maximo } : {}).merge(chave => itens.first(maximo))
  end

  # -> os itens com todas as palavras da busca no nome (`nome`: o texto de cada item). Sem busca, todos.
  def filtrar(itens, busca)
    palavras = comparavel(busca).split
    return itens if palavras.empty?

    itens.select do |item|
      texto = comparavel(yield(item))
      palavras.all? { |palavra| texto.include?(palavra) }
    end
  end
end
