# O conector do WAHA procura o contato a cada mensagem com OR de cinco caminhos (#1106): as três chaves
# abaixo em custom_attributes, LOWER(identifier) e phone_number. Um OR só usa índice quando TODOS os
# caminhos têm índice; sem estes, o Postgres avalia linha a linha todos os contatos da conta.
class AddWahaContactLookupIndexes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  WAHA_KEYS = %w[waha_whatsapp_chat_id waha_whatsapp_lid waha_whatsapp_jid].freeze

  def up
    # O statement_timeout de 14 s do database.yml não pode matar um CREATE INDEX CONCURRENTLY no meio.
    execute 'SET statement_timeout = 0'
    indexes.each do |name, expression|
      drop_if_invalid(name)
      add_index :contacts, expression, name: name, algorithm: :concurrently, if_not_exists: true
    end
  end

  def down
    execute 'SET statement_timeout = 0'
    indexes.each_key { |name| remove_index :contacts, name: name, algorithm: :concurrently, if_exists: true }
  end

  private

  def indexes
    WAHA_KEYS.to_h { |key| ["idx_contacts_account_lower_#{key}", "account_id, LOWER(custom_attributes ->> '#{key}')"] }
             .merge('idx_contacts_account_lower_identifier' => 'account_id, LOWER(identifier)')
  end

  # Build concorrente interrompido deixa o índice INVALID; o if_not_exists o pularia para sempre.
  def drop_if_invalid(name)
    invalid = select_value(<<~SQL.squish)
      SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = #{connection.quote(name)} AND NOT i.indisvalid
    SQL
    execute("DROP INDEX CONCURRENTLY IF EXISTS #{connection.quote_column_name(name)}") if invalid
  end
end
