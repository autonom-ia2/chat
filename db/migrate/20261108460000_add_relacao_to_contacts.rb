# Este contato é (#2084/#2085): interessado (0, o padrão), parceiro do mercado (1) ou não é negócio (2). Parceiro e não é
# negócio não viram card sozinhos e ficam fora dos Números (Crm::Relacao).
# - O default é constante: no PostgreSQL 11+ o add_column é só metadado, sem reescrever a tabela. O lock_timeout do
#   StrongMigrations cobre o ACCESS EXCLUSIVE curto.
# - O índice parcial guarda só os contatos fora do funil (poucos), por conta, para o NOT EXISTS dos Números. É criado
#   concurrently, fora da transação, e o statement_timeout de 14 s do database.yml é zerado só durante ele: contacts é
#   grande, e o CREATE INDEX CONCURRENTLY morto no meio deixaria um índice inválido. Se uma rodada anterior caiu no
#   meio, o índice inválido é refeito. Rodar de novo não muda nada.
class AddRelacaoToContacts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'idx_contacts_relacao_fora_do_funil'.freeze

  def up
    add_column :contacts, :relacao, :smallint, default: 0, null: false, if_not_exists: true
    sem_limite_de_tempo do
      remove_index :contacts, name: INDICE, algorithm: :concurrently if indice_invalido?
      add_index :contacts, :account_id, name: INDICE, where: 'relacao <> 0', algorithm: :concurrently, if_not_exists: true
    end
  end

  def down
    sem_limite_de_tempo { remove_index :contacts, name: INDICE, algorithm: :concurrently, if_exists: true }
    remove_column :contacts, :relacao, if_exists: true
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
