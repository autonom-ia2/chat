# O CATÁLOGO DE COBERTURAS da Universal (#3249), lido por `coberturas_dos_planos`: os planos e o valor de cada cobertura,
# SEM PREÇO (preço só na cotação). Vem de `Universal::Cliente#beneficios`.
#
# O NOME DA COBERTURA sai de `beneficios[]` (`idBeneficio` -> `descricao`); o plano traz só o id e o valor. Nomes e
# valores passam por `strip`: a Universal manda TAB no fim de alguns nomes ("Exclusive USA +\t") e espaço antes de
# "SIM". O valor fica como veio ("$40.000" no internacional, em dólar; "R$ 300.000" no nacional).
#
# O NOME DO PLANO é casado pela forma normalizada (`normalizar`): minúsculas, sem acento, sem "+", sem a palavra "usa",
# espaços e TAB colapsados. Vale a igualdade; sem nenhum igual, vale o prefixo de palavra inteira ("Anual" casa os
# três anuais). Assim "Master", "Master +" e "Master USA +" chegam ao mesmo plano.
#
# FATO MEDIDO (26/11/2026): as coberturas de "Master +", "Value +" e "Exclusive +" (Europa e demais destinos) são
# idênticas, item a item, às de "Master USA +", "Value USA +" e "Exclusive USA +" (31, 33 e 33 itens, 0 diferenças). O
# catálogo internacional só traz as versões "USA +" e os anuais, e por isso responde pelos dois; é o que a
# normalização sem "usa" aproveita.
module Autonomia::Agents::Tools::Native::SeguroViagem::CatalogoDeCoberturas
  module_function

  # -> [{ 'plano' => nome no catálogo, 'chave' => nome normalizado, 'coberturas' => [{ 'nome', 'valor' }] }]
  def planos(catalogo)
    nomes = nomes_das_coberturas(catalogo)
    Array(catalogo['produtos']).filter_map do |produto|
      next unless produto.is_a?(Hash)

      nome = produto['descricao'].to_s.strip
      next if nome.empty?

      { 'plano' => nome, 'chave' => normalizar(nome), 'coberturas' => coberturas(produto, nomes) }
    end
  end

  # -> [planos escolhidos, nomes pedidos que não casam com nenhum]. Lista vazia: todos.
  def escolher(planos, pedidos)
    nomes = Array(pedidos).map { |pedido| pedido.to_s.strip }.reject(&:empty?)
    return [planos, []] if nomes.empty?

    achados = nomes.index_with { |nome| achar(planos, nome) }
    [achados.values.flatten.uniq { |plano| plano['plano'] }, achados.select { |_nome, casados| casados.empty? }.keys]
  end

  def normalizar(nome)
    I18n.transliterate(nome.to_s).downcase.delete('+').split.reject { |palavra| palavra == 'usa' }.join(' ')
  end

  def achar(planos, nome)
    chave = normalizar(nome)
    return [] if chave.empty?

    iguais = planos.select { |plano| plano['chave'] == chave }
    return iguais if iguais.any?

    planos.select { |plano| plano['chave'].start_with?("#{chave} ") }
  end

  def nomes_das_coberturas(catalogo)
    Array(catalogo['beneficios']).each_with_object({}) do |beneficio, nomes|
      next unless beneficio.is_a?(Hash)

      nome = beneficio['descricao'].to_s.strip
      nomes[beneficio['idBeneficio']] = nome unless nome.empty?
    end
  end

  # A cobertura cujo id o catálogo não nomeia fica de fora: sem nome, o modelo não tem o que dizer dela.
  def coberturas(produto, nomes)
    Array(produto['beneficios']).filter_map do |beneficio|
      next unless beneficio.is_a?(Hash)

      nome = nomes[beneficio['idBeneficio']]
      { 'nome' => nome, 'valor' => beneficio['valor'].to_s.strip } if nome
    end
  end

  private_class_method :achar, :nomes_das_coberturas, :coberturas
end
