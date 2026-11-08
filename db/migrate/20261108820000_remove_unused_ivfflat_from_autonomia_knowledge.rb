# RAG v2, F1 (#1431): tira o índice ivfflat de `autonomia_agent_knowledge.embedding`, que nunca é usado.
# - Ele foi criado com a operação padrão (distância L2), e a busca do Retriever pede cosseno: o Postgres não o usa.
#   Medido em 08/11/2026 nas 2 stacks: 0 usos (pg_stat_user_indexes), 77 MB na hub2you e 21 MB na autonomia. A busca
#   continua exata, filtrada pelo agente, como já é hoje.
# - O HNSW por cosseno NÃO entra aqui: é busca aproximada e, com o filtro por agente, pode devolver outros candidatos.
#   Só entra numa migration própria se a medida local mostrar o mesmo hit@12 da busca exata (desenho da F1).
# - Concorrente: não trava a tabela. O statement_timeout de 14 s do database.yml fica zerado só nesta migration, e a
#   espera por uma transação longa para em LOCK_TIMEOUT: o deploy falha em vez de ficar preso (rodar de novo resolve).
# - O down recria o ivfflat como era. Rodar de novo não muda nada.
class RemoveUnusedIvfflatFromAutonomiaKnowledge < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'idx_autonomia_knowledge_embedding'.freeze
  LOCK_TIMEOUT = '5min'.freeze

  def up
    sem_limite_de_tempo { remove_index :autonomia_agent_knowledge, name: INDICE, algorithm: :concurrently, if_exists: true }
  end

  def down
    sem_limite_de_tempo do
      add_index :autonomia_agent_knowledge, :embedding, name: INDICE, using: :ivfflat, algorithm: :concurrently,
                                                        if_not_exists: true
    end
  end

  private

  def sem_limite_de_tempo
    anterior = select_value('SHOW statement_timeout')
    espera = select_value('SHOW lock_timeout')
    safety_assured { execute "SET statement_timeout = 0; SET lock_timeout = #{connection.quote(LOCK_TIMEOUT)}" }
    yield
  ensure
    safety_assured { execute "SET statement_timeout = #{connection.quote(anterior)}" } if anterior
    safety_assured { execute "SET lock_timeout = #{connection.quote(espera)}" } if espera
  end
end
