# AS LISTAS QUE VÃO AO MODELO (#2858): marcas da FIPE, modelos de uma marca, cidades de um estado. A contagem vai antes
# da lista (se o corte do turno pegar o fim, o modelo ainda sabe quantos eram) e a lista tem teto. A busca é local, sobre
# a lista inteira da fonte (ou do cache): todas as palavras no nome, sem acento e sem caixa. A ordem por relevância
# (`em_ordem`) vem antes do corte, para o que mais se parece com a busca não ficar de fora.
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

  # -> os itens na ordem de relevância para a busca, ANTES do corte (`texto`: o texto de cada item). Três grupos, cada um
  # na ordem em que veio (a da fonte, em geral a do código):
  #   0. o texto começa pelas palavras da busca ("parafuso" em "-- Parafusos autoperfurantes");
  #   1. cada palavra da busca começa uma palavra do texto ("Outros parafusos para madeira");
  #   2. o resto (a palavra no meio de outra: "asma" em "Histoplasmose").
  # `desempate` (opcional): um número por item, menor primeiro, dentro de cada grupo e antes da ordem da fonte.
  def em_ordem(itens, busca, desempate: ->(_item) { 0 })
    procuradas = palavras(busca)
    itens.each_with_index.sort_by do |item, posicao|
      [grupo(palavras(yield(item)), procuradas), desempate.call(item), posicao]
    end.map(&:first)
  end

  # As palavras comparáveis, só com letras e números ("-- Parafusos," -> ["parafusos"]).
  def palavras(texto)
    comparavel(texto).split.map { |palavra| palavra.delete('^a-z0-9') }.reject(&:empty?)
  end

  def grupo(palavras_do_texto, procuradas)
    return 0 if procuradas.each_with_index.all? { |palavra, indice| palavras_do_texto[indice]&.start_with?(palavra) }
    return 1 if procuradas.all? { |palavra| palavras_do_texto.any? { |parte| parte.start_with?(palavra) } }

    2
  end
end
