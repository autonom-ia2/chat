class AddIndexesToAutonomiaAgentFaqSuggestions < ActiveRecord::Migration[7.2]
  # Índices CONCURRENTLY (não bloqueiam escritas no RDS compartilhado); exige rodar fora de transação,
  # por isso separada da migration da tabela (20260903150000). if_not_exists = reexecução idempotente.
  disable_ddl_transaction!

  def change
    add_index :autonomia_agent_faq_suggestions, %i[autonomia_agent_id status],
              name: 'idx_autonomia_faq_suggestions_agent_status', algorithm: :concurrently, if_not_exists: true
    add_index :autonomia_agent_faq_suggestions, %i[autonomia_agent_id question_hash],
              name: 'idx_autonomia_faq_suggestions_agent_hash', algorithm: :concurrently, if_not_exists: true
    add_index :autonomia_agent_faq_suggestions, :account_id,
              name: 'idx_autonomia_faq_suggestions_account', algorithm: :concurrently, if_not_exists: true
    add_index :autonomia_agent_faq_suggestions, :conversation_id,
              name: 'idx_autonomia_faq_suggestions_conversation', algorithm: :concurrently, if_not_exists: true
  end
end
