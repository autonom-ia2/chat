# #2211 — a busca da lista de conversas acha "João" digitando "joao", no nome do contato, no texto da mensagem e no áudio
# transcrito. Três índices trigram (GIN) sobre lower(translate(coluna, ...)) escrito por extenso, com a tabela de letras
# de SearchService::SemAcento — a mesma expressão que a consulta usa. Sem extensão (unaccent) e sem função no banco: o
# db/schema.rb guarda a expressão e carrega num banco novo.
# - Criados concurrently, fora da transação, sem travar escrita. O statement_timeout de 14 s do database.yml é zerado só
#   durante cada CREATE INDEX: messages é grande, e o CREATE INDEX CONCURRENTLY morto no meio deixaria um índice
#   inválido.
# - Se uma rodada anterior caiu no meio, o índice inválido é apagado e refeito. Rodar de novo não muda nada.
class AddIndicesDaBuscaSemAcento < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICES = [
    [:contacts, 'name', 'idx_contacts_nome_sem_acento_trgm'],
    [:messages, 'content', 'idx_messages_conteudo_sem_acento_trgm'],
    [:attachments, "(meta ->> 'transcribed_text')", 'idx_attachments_transcricao_sem_acento_trgm']
  ].freeze

  def up
    INDICES.each do |tabela, coluna, nome|
      sem_limite_de_tempo do
        remove_index tabela, name: nome, algorithm: :concurrently if indice_invalido?(nome)
        add_index tabela, "#{SearchService::SemAcento.sql(coluna)} gin_trgm_ops",
                  using: :gin, name: nome, algorithm: :concurrently, if_not_exists: true
      end
    end
  end

  def down
    INDICES.reverse_each do |tabela, _coluna, nome|
      sem_limite_de_tempo { remove_index tabela, name: nome, algorithm: :concurrently, if_exists: true }
    end
  end

  private

  def sem_limite_de_tempo
    anterior = select_value('SHOW statement_timeout')
    safety_assured { execute 'SET statement_timeout = 0' }
    yield
  ensure
    safety_assured { execute "SET statement_timeout = #{connection.quote(anterior)}" } if anterior
  end

  def indice_invalido?(nome)
    select_value("SELECT NOT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = '#{nome}'") == true
  end
end
