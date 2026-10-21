# Convite de reunião no e-mail (#2042): a versão anterior do mesmo convite (ConversaCanal::ConviteSubstituido) é achada
# pela chave do UID em `additional_attributes.convite_uid_sha256`, por índice, sem varrer o texto das mensagens.
# - Índice parcial (só as mensagens com convite) e concorrente: não trava a escrita em `messages`.
# - O statement_timeout de 14 s do database.yml não pode matar o CREATE INDEX CONCURRENTLY no meio (messages tinha
#   138 MB na hub2you em 21/10/2026): zerado só nesta migration e devolvido ao fim.
# - Se uma rodada anterior caiu no meio, o índice inválido é refeito. Rodar de novo não muda nada.
# - O preenchimento dos convites já recebidos fica na migration seguinte (20261108320000).
class AddConviteUidIndexToMessages < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'index_messages_on_convite_uid_sha256'.freeze

  def up
    sem_limite_de_tempo do
      remove_index :messages, name: INDICE, algorithm: :concurrently if indice_invalido?
      add_index :messages, "(additional_attributes ->> 'convite_uid_sha256')", name: INDICE,
                                                                               where: "(additional_attributes ->> 'convite_uid_sha256') IS NOT NULL",
                                                                               algorithm: :concurrently, if_not_exists: true
    end
  end

  def down
    sem_limite_de_tempo { remove_index :messages, name: INDICE, algorithm: :concurrently, if_exists: true }
  end

  private

  def sem_limite_de_tempo
    anterior = select_value('SHOW statement_timeout')
    safety_assured { execute 'SET statement_timeout = 0' }
    yield
  ensure
    safety_assured { execute "SET statement_timeout = #{connection.quote(anterior)}" } if anterior
  end

  def indice_invalido?
    select_value("SELECT NOT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = '#{INDICE}'") == true
  end
end
