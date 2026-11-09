# #1431 (PR 1b) — o trecho de item (CortePorSecao: item de lista, verbete, fileira de tabela) só serve para achar. No
# lugar dele volta o trecho da seção que o contém (`trecho_da_secao`), com a menor distância entre ele e os itens que o
# trouxeram, e cada trecho uma vez só, na ordem do melhor. O item sem `trecho_da_secao` (atravessa dois trechos da
# seção) ou cujo trecho não está no escopo volta ele mesmo. Sem item entre os candidatos (todo material lido antes do
# 1b), a lista volta igual.
#
# Saiu do Retriever no #2810, sem mudar o comportamento: a busca de hoje e a busca híbrida usam a mesma troca.
class Autonomia::Agents::SecoesDosItens
  # escopo: o mesmo escopo da busca (agente, prontos, sem material reprovado).
  def initialize(escopo)
    @escopo = escopo
  end

  def trocar(entries)
    itens = entries.select { |entry| item?(entry) }
    return entries if itens.empty?

    secoes = secoes_dos(itens, entries)
    entries.map { |entry| secoes.fetch(chave_da_secao(entry), entry) }.uniq(&:id)
  end

  private

  # O trecho da seção de cada um: o do item é o pai; o do trecho de seção, ele mesmo.
  def chave_da_secao(entry)
    [entry.source_id, item?(entry) ? entry.metadata['trecho_da_secao'] : entry.chunk_index]
  end

  def item?(entry)
    metadata = entry.metadata.to_h
    metadata['material_type'] == 'item' && !metadata['trecho_da_secao'].nil?
  end

  # { [source_id, chunk_index] => trecho da seção }, numa consulta só, no mesmo escopo da busca, com `neighbor_distance`
  # no SELECT (o atributo de sempre, que o Answerer e o placar leem): a menor entre a do trecho, se veio, e a dos itens.
  def secoes_dos(itens, entries)
    pais = itens.map { |item| chave_da_secao(item) }.uniq
    @escopo.where(source_id: pais.map(&:first).uniq, chunk_index: pais.map(&:last).uniq)
           .select(Arel.sql("autonomia_agent_knowledge.*, #{distancia_por_trecho(pais, entries)} AS neighbor_distance"))
           .select { |secao| pais.include?([secao.source_id, secao.chunk_index]) }
           .index_by { |secao| [secao.source_id, secao.chunk_index] }
  end

  # CASE com a distância de cada trecho de seção (a menor entre a dele, se veio, e a dos itens dele), sanitizado.
  def distancia_por_trecho(pais, entries)
    distancias = entries.group_by { |entry| chave_da_secao(entry) }
                        .transform_values { |mesma_secao| mesma_secao.map { |entry| entry.neighbor_distance.to_f }.min }
    casos = pais.map do |source_id, chunk_index|
      Autonomia::Agents::KnowledgeEntry.sanitize_sql_array(['WHEN source_id = ? AND chunk_index = ? THEN ?', source_id, chunk_index,
                                                            distancias[[source_id, chunk_index]]])
    end
    "(CASE #{casos.join(' ')} END)::float"
  end
end
