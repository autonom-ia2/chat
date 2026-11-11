# A DESCRIÇÃO COMPLETA de um código da NCM (#2858, achado do teste em produção de 11/11/2026). A tabela do Siscomex dá a
# cada nível só o texto relativo ao pai, com os traços do nível e os dois-pontos do grupo: "0901.2 | - Café torrado:" e,
# abaixo dele, "0901.21.00 | -- Não descafeinado". Sozinho, o código da nota dizia só "Não descafeinado".
#   - `limpa`: o texto sem os traços do começo e sem o ":" do fim ("Café torrado");
#   - `completa`: o código sobe pela hierarquia dos itens que vieram (o pai é o código cujos dígitos começam os dele):
#     subposição (5 e 6 dígitos) e item (7), de cima para baixo, e o texto dele por último, com vírgula ("Café torrado,
#     não descafeinado"). A posição (4 dígitos) só entra no código da nota filho direto dela (um traço só e nenhuma
#     subposição no meio): "0901.90.00 | - Outros" sozinho não diz o quê. O capítulo (2) e a posição têm o texto inteiro.
# Trabalha sobre o `Nivel` (o texto de cada item já lido). Sem regex: `start_with?`, `delete_prefix` e `delete_suffix`.
module Autonomia::FerramentasProntas::Fontes::Ncm::Descricao
  SEPARADOR = ', '.freeze

  module_function

  # "-- Não descafeinado" -> "Não descafeinado"; "- Café torrado:" -> "Café torrado".
  def limpa(texto)
    resto = texto.to_s.strip
    resto = resto.delete_prefix('-').lstrip while resto.start_with?('-')
    resto.delete_suffix(':').rstrip
  end

  # Os níveis da mesma resposta (e da chamada a mais) pelos dígitos, montado uma vez: o pai de cada nível se acha sem
  # varrer a lista.
  def indice(niveis)
    niveis.index_by(&:digitos)
  end

  # `indice`: o que `indice` monta. Os textos de cima perdem o ponto final; os de baixo começam com minúscula, menos a
  # sigla ("PVC").
  def completa(nivel, indice)
    de_cima = acima(nivel, indice).map { |pai| pai.propria.delete_suffix('.') }
    partes = (de_cima + [nivel.propria]).reject(&:empty?).uniq
    ([partes.first] + partes.drop(1).map { |parte| minuscula(parte) }).join(SEPARADOR)
  end

  # Os pais que vieram, de cima para baixo: o código com os primeiros 4, 5, 6 e 7 dígitos deste. Sem subposição entre
  # eles, sobra só a posição, que entra no código da nota filho direto dela.
  def acima(nivel, indice)
    return [] if nivel.digitos.length <= ncm::POSICAO

    pais = (ncm::POSICAO...nivel.digitos.length).filter_map { |tamanho| indice[nivel.digitos.first(tamanho)] }
    subposicoes = pais.drop_while { |pai| pai.digitos.length == ncm::POSICAO }
    return subposicoes if subposicoes.any?

    nivel.da_nota? && nivel.tracos == 1 ? pais : []
  end

  def minuscula(texto)
    segunda = texto[1].to_s
    segunda == segunda.downcase ? "#{texto[0].downcase}#{texto[1..]}" : texto
  end

  def ncm
    Autonomia::FerramentasProntas::Fontes::Ncm
  end
end
