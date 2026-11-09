# #2810 (Refs #1431): índice GIN de expressão para a busca por palavra da busca híbrida (BuscaHibrida), com o texto em
# português. Aditiva: sem coluna nova e sem reescrever a tabela; criada sem travar a escrita (concurrently). Só é usada
# com a flag `rag_busca_hibrida`; sem ela, nada lê o índice. Rollback: a migration desfaz o índice.
class AddIndiceDeTextoNaBaseDoAgente < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :autonomia_agent_knowledge, "to_tsvector('portuguese', content)",
              using: :gin, algorithm: :concurrently, if_not_exists: true,
              name: 'index_autonomia_agent_knowledge_on_texto_pt'
  end
end
