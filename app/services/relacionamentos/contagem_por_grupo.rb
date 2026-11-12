# Quantos há em cada grupo da Lista de Relacionamentos (#2894), numa consulta só: um COUNT(*) FILTER por grupo sobre o
# mesmo escopo que a lista usa. `grupos` é { id do grupo => condição em SQL }, escrita no código e já com os valores.
module Relacionamentos::ContagemPorGrupo
  def self.call(escopo, grupos)
    colunas = grupos.values.map { |condicao| Arel.sql("COUNT(*) FILTER (WHERE #{condicao})") }
    grupos.keys.zip(escopo.pick(*colunas)).to_h
  end
end
