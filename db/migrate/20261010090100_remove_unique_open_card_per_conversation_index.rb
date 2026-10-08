# Multifunil (#1142): uma conversa pode ter mais de um card aberto — duas cotações, ou uma venda e um atendimento.
# O índice único (um card aberto por conversa principal) era a última trava. Quem escolhe "o card da conversa" agora
# é o Crm::Cards::ConversationCardFinder (assunto atual), desde a #1141.
#
# Sem volta de propósito: depois que existirem dois cards abertos na mesma conversa, recriar o índice falharia ou
# exigiria apagar/arquivar cards reais. O recuo seguro é desligar o recurso, não restaurar a trava.
# idx_crm_cards_conversation (account_id, conversation_id, status, id) continua atendendo as buscas por conversa.
class RemoveUniqueOpenCardPerConversationIndex < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    remove_index :crm_cards, name: 'idx_crm_cards_unique_open_conversation', algorithm: :concurrently, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Recriar o índice exigiria apagar cards abertos reais; desligue o recurso.'
  end
end
