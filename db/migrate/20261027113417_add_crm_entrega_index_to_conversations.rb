# Motor de entrega (#1454): o HandoffDrainJob procura a cada 2 minutos, em todas as contas, as conversas que o motor
# segura (marca `crm_entrega` nos atributos adicionais). Índice parcial: só as marcadas entram, então ele fica do tamanho
# da fila de espera, e a varredura não lê a tabela de conversas. Só índice, nenhuma coluna nova.
class AddCrmEntregaIndexToConversations < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :conversations, :id,
              name: 'index_conversations_on_crm_entrega_pendente',
              where: "(additional_attributes ->> 'crm_entrega') IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
