# G22 (#2414, exemplo 8, passo 9): o card guarda quem pediu a inclusão (o RH que mandou a lista), para o aviso de sexta
# achar o RH de cada empresa e listar quem ainda não mandou documento. Quem vai gravar é a criação dos cards do passo 3
# (G24), que não está neste commit: até lá a coluna fica vazia e o salvar recusa a condição que a lê
# (Autonomia::Automacao::Solicitados::GRAVADORES).
#
# crm_cards é grande: fora da transação, o índice entra concurrently (parcial, só os cards com solicitante) e a chave
# estrangeira entra NOT VALID e é validada depois (VALIDATE pega só SHARE UPDATE EXCLUSIVE; leitura e escrita seguem).
# Contato apagado deixa o card sem solicitante (on_delete nullify); a mescla de contatos move o solicitante.
class AddSolicitanteToCrmCards < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'idx_crm_cards_solicitante'.freeze

  def up
    add_column :crm_cards, :solicitante_contact_id, :bigint, if_not_exists: true
    add_index :crm_cards, %i[account_id solicitante_contact_id status],
              name: INDICE, where: 'solicitante_contact_id IS NOT NULL', algorithm: :concurrently, if_not_exists: true
    unless foreign_key_exists?(:crm_cards, :contacts, column: :solicitante_contact_id)
      add_foreign_key :crm_cards, :contacts, column: :solicitante_contact_id, on_delete: :nullify, validate: false
    end
    validate_foreign_key :crm_cards, :contacts, column: :solicitante_contact_id
  end

  def down
    remove_foreign_key :crm_cards, :contacts, column: :solicitante_contact_id, if_exists: true
    remove_index :crm_cards, name: INDICE, algorithm: :concurrently, if_exists: true
    remove_column :crm_cards, :solicitante_contact_id, if_exists: true
  end
end
