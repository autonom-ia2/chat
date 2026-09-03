class AddReplySourceIndexesToAutonomiaAgentEvents < ActiveRecord::Migration[7.2]
  # Índices CONCURRENTLY (não bloqueiam escritas na tabela no RDS compartilhado). Exige rodar fora de
  # transação, por isso vive separada da migration de colunas (20260903140000). if_not_exists torna a
  # reexecução idempotente caso um CREATE INDEX CONCURRENTLY anterior tenha ficado pela metade.
  disable_ddl_transaction!

  def change
    add_index :autonomia_agent_events, :message_id,
              name: 'idx_autonomia_events_message', algorithm: :concurrently, if_not_exists: true
    add_index :autonomia_agent_events, :used_entry_ids, using: :gin,
                                                        name: 'idx_autonomia_events_used_entry_ids', algorithm: :concurrently, if_not_exists: true
  end
end
