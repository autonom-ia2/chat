# Este contato é (#2084/#2085): interessado (0, o padrão), parceiro do mercado (1) ou não é negócio (2). Parceiro e não é
# negócio não viram card sozinhos e ficam fora dos Números (Crm::Relacao). O default é constante: no PostgreSQL 11+ o
# add_column é só metadado, sem reescrever a tabela. O índice parcial só guarda os contatos fora do funil (poucos), para
# o NOT EXISTS dos Números; é criado concurrently, fora da transação.
class AddRelacaoToContacts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'idx_contacts_relacao_fora_do_funil'.freeze

  def up
    add_column :contacts, :relacao, :smallint, default: 0, null: false, if_not_exists: true
    add_index :contacts, :account_id, name: INDICE, where: 'relacao <> 0', algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :contacts, name: INDICE, algorithm: :concurrently, if_exists: true
    remove_column :contacts, :relacao, if_exists: true
  end
end
