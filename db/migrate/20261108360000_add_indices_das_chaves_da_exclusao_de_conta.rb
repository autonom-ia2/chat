# Exclusão da conta (#2133): chaves estrangeiras sem índice que comece pela coluna. Ao apagar o pai, o gatilho da chave
# procura os filhos com `WHERE coluna = $1`; sem índice, lê a tabela inteira (de todas as contas) a cada linha apagada.
# - crm_memoria_fatos.card_id e .contact_id: cascata de cada card e de cada contato apagado. Os índices que existem
#   começam por account_id e não servem a essa busca.
# - autonomia_agent_inboxes.inbox_id: nullify de cada caixa apagada. Os dois índices em inbox_id são parciais (só os
#   vínculos vivos) e não servem.
# Nome explícito: há outros índices em autonomia_agent_inboxes.inbox_id, e o remove_index só pela coluna é ambíguo.
class AddIndicesDasChavesDaExclusaoDeConta < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICES = [
    [:crm_memoria_fatos, :card_id, 'index_crm_memoria_fatos_on_card_id'],
    [:crm_memoria_fatos, :contact_id, 'index_crm_memoria_fatos_on_contact_id'],
    [:autonomia_agent_inboxes, :inbox_id, 'index_autonomia_agent_inboxes_on_inbox_id']
  ].freeze

  def up
    INDICES.each { |tabela, coluna, nome| add_index tabela, coluna, name: nome, algorithm: :concurrently, if_not_exists: true }
  end

  def down
    INDICES.each { |tabela, _coluna, nome| remove_index tabela, name: nome, algorithm: :concurrently, if_exists: true }
  end
end
