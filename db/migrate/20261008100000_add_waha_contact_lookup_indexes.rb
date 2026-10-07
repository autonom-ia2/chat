# O conector do WAHA procura o contato a cada mensagem com OR de cinco caminhos (#1106): as três chaves
# abaixo em custom_attributes, LOWER(identifier) e phone_number. Um OR só usa índice quando TODOS os
# caminhos têm índice; sem estes, o Postgres avalia linha a linha todos os contatos da conta.
class AddWahaContactLookupIndexes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  WAHA_KEYS = %w[waha_whatsapp_chat_id waha_whatsapp_lid waha_whatsapp_jid].freeze

  def up
    WAHA_KEYS.each do |key|
      add_index :contacts, "account_id, LOWER(custom_attributes ->> '#{key}')",
                name: "idx_contacts_account_lower_#{key}", algorithm: :concurrently, if_not_exists: true
    end
    add_index :contacts, 'account_id, LOWER(identifier)',
              name: 'idx_contacts_account_lower_identifier', algorithm: :concurrently, if_not_exists: true
  end

  def down
    (WAHA_KEYS.map { |key| "idx_contacts_account_lower_#{key}" } + ['idx_contacts_account_lower_identifier']).each do |name|
      remove_index :contacts, name: name, algorithm: :concurrently, if_exists: true
    end
  end
end
