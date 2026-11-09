# RAG v2 (#2810, Refs #1431): índice GIN de expressão para a busca por palavra da busca híbrida (BuscaHibrida), com o
# texto em português. Só é lido com a flag `rag_busca_hibrida`; sem ela, nada usa o índice.
# - Aditiva: sem coluna nova e sem reescrever a tabela. A expressão é a mesma da consulta (to_tsvector('portuguese',
#   content)), para o Postgres usar o índice.
# - Concorrente: não trava a escrita. O statement_timeout de 14 s do database.yml fica zerado só nesta migration (um GIN
#   em to_tsvector passa dele), e a espera por uma transação longa para em LOCK_TIMEOUT: o deploy falha em vez de ficar
#   preso (rodar de novo resolve), como na 20261108820000 do #2745.
# - O down remove o índice, também concorrente. Rodar de novo não muda nada.
class AddIndiceDeTextoNaBaseDoAgente < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'index_autonomia_agent_knowledge_on_texto_pt'.freeze
  EXPRESSAO = "to_tsvector('portuguese', content)".freeze
  LOCK_TIMEOUT = '5min'.freeze

  def up
    sem_limite_de_tempo do
      add_index :autonomia_agent_knowledge, EXPRESSAO, name: INDICE, using: :gin, algorithm: :concurrently, if_not_exists: true
    end
  end

  def down
    sem_limite_de_tempo { remove_index :autonomia_agent_knowledge, name: INDICE, algorithm: :concurrently, if_exists: true }
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
