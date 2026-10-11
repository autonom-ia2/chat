# Link de agendamento por conta (#1299): `/a/<conta>/<página>` no lugar de `/a/<página>`.
#
# - `crm_booking_account_addresses`: o endereço da conta (o `<conta>`). Tabela própria, sem coluna em `accounts`. Dois
#   índices únicos: um endereço por conta e um dono por endereço, na instalação inteira. Some junto com a conta.
# - O nome da página (`short_name`) deixa de ser único na instalação e passa a ser único por conta.
#
# A ordem garante que a tabela nunca fica sem unicidade: o índice novo `(account_id, short_name)` nasce (concorrente)
# ANTES de o índice global sair (concorrente). Enquanto os dois existem, vale a regra mais dura, a global.
#
# Uma criação concorrente interrompida deixa o índice no banco marcado como inválido, e ele não garante unicidade.
# Rodar de novo o apaga e recria, em vez de pular por já existir um índice com o nome.
#
# A tabela nova tem chave estrangeira para `accounts`, e criá-la pede uma trava curta em `accounts`. Com `lock_timeout`,
# se alguma transação longa estiver segurando `accounts`, a migration falha em 5 s (e pode rodar de novo) em vez de
# deixar toda escrita em contas esperando atrás dela.
#
# `down`: recria o índice global antes de tirar o por conta. Ele só volta se nenhum nome se repetir entre contas;
# havendo repetição, o Postgres recusa, e é preciso renomear as páginas repetidas antes de desfazer.
class ScopeBookingShortNamesToAccount < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  PAGES = :crm_agent_booking_profiles
  ADDRESSES = :crm_booking_account_addresses
  PER_ACCOUNT_INDEX = 'index_crm_agent_booking_profiles_on_account_and_short_name'.freeze
  GLOBAL_INDEX = 'index_crm_agent_booking_profiles_on_short_name'.freeze

  def up
    create_addresses
    remove_index PAGES, name: PER_ACCOUNT_INDEX, algorithm: :concurrently if invalid_index?(PER_ACCOUNT_INDEX)
    add_index PAGES, [:account_id, :short_name], unique: true, algorithm: :concurrently, if_not_exists: true, name: PER_ACCOUNT_INDEX
    remove_index PAGES, name: GLOBAL_INDEX, algorithm: :concurrently, if_exists: true
  end

  def down
    remove_index PAGES, name: GLOBAL_INDEX, algorithm: :concurrently if invalid_index?(GLOBAL_INDEX)
    add_index PAGES, :short_name, unique: true, algorithm: :concurrently, if_not_exists: true, name: GLOBAL_INDEX
    remove_index PAGES, name: PER_ACCOUNT_INDEX, algorithm: :concurrently, if_exists: true
    drop_table ADDRESSES, if_exists: true
  end

  private

  def create_addresses
    execute("SET lock_timeout TO '5s'")
    create_table ADDRESSES, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :name, null: false
      t.timestamps
      t.index :name, unique: true
    end
  ensure
    execute('RESET lock_timeout')
  end

  def invalid_index?(name)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_index JOIN pg_class ON pg_class.oid = pg_index.indexrelid
      WHERE pg_class.relname = #{connection.quote(name)} AND NOT pg_index.indisvalid
    SQL
  end
end
