# #3063, item 2: limite de mensagens por cliente e horário de envio, definidos pela conta (decisões do Rodrigo, 19/11).
# - `envios_ao_cliente`: o contador do limite. Uma linha por mensagem de campanha ou de automação que o porteiro
#   (Autonomia::RitmoDeEnvio::Porteiro) liberou para o cliente. O aviso de renovação da carteira não passa por ele e não
#   conta. O índice [account_id, contact_id, enviado_em] serve a conta "quantas nos últimos N dias" e começa pela conta,
#   então account_id não ganha índice próprio; contact_id ganha o dele para a cascata. As linhas mais velhas que o maior
#   período escolhível (30 dias) são apagadas pela varredura.
# - `adiado_ate` nos destinatários de campanha (WhatsApp Oficial e SMS, WhatsApp API, e-mail): fora do limite ou do
#   horário, o destinatário espera aqui em vez de ser descartado; a varredura o devolve ao envio na hora. Nula = nunca foi
#   adiado. Índice parcial só com as linhas adiadas.
#
# Chaves: contato em cascata (apagar a pessoa apaga a conta dela no limite); conta sem cascata, como as outras tabelas
# da conta: a exclusão da conta (Autonomia::ExclusaoDaConta) apaga as linhas antes do DELETE da conta.
#
# Travas: o ADD COLUMN sem default é só metadado (ACCESS EXCLUSIVE pelo instante do comando, com o lock_timeout curto do
# strong_migrations). Os índices das tabelas de destinatários, que são grandes, entram concurrently, sem bloquear
# escrita. Sem backfill. Cada passo pode rodar de novo sem erro se o deploy cair no meio.
class CreateEnviosAoCliente < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  RECIPIENT_TABLES = %i[campaign_recipients whatsapp_api_campaign_recipients email_campaign_recipients].freeze

  def up
    # Sem timestamps: a linha nasce e morre sem mudar; `enviado_em` é a única data que ela tem.
    create_table :envios_ao_cliente, if_not_exists: true do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.datetime :enviado_em, null: false
      t.string :origem, null: false
      t.index %i[account_id contact_id enviado_em], name: 'idx_envios_ao_cliente_conta_contato_quando'
      t.index :enviado_em, name: 'idx_envios_ao_cliente_enviado_em'
    end

    RECIPIENT_TABLES.each do |table|
      add_column table, :adiado_ate, :datetime, if_not_exists: true
      remove_invalid_index(table, "idx_#{table}_adiado_ate")
      add_index table, :adiado_ate, where: 'adiado_ate IS NOT NULL', algorithm: :concurrently, if_not_exists: true,
                                    name: "idx_#{table}_adiado_ate"
    end
  end

  def down
    RECIPIENT_TABLES.each do |table|
      remove_index table, name: "idx_#{table}_adiado_ate", algorithm: :concurrently, if_exists: true
      remove_column table, :adiado_ate, if_exists: true
    end
    drop_table :envios_ao_cliente, if_exists: true
  end

  private

  # Um CREATE INDEX CONCURRENTLY que caiu no meio deixa o índice INVALID com o nome; o if_not_exists pularia ele.
  def remove_invalid_index(table, name)
    invalid = select_value(<<~SQL.squish)
      SELECT 1 FROM pg_index JOIN pg_class ON pg_class.oid = pg_index.indexrelid
      WHERE pg_class.relname = #{connection.quote(name)} AND NOT pg_index.indisvalid
    SQL
    remove_index table, name: name, algorithm: :concurrently if invalid
  end
end
