class CreateAutonomiaAgentFaqSuggestions < ActiveRecord::Migration[7.2]
  # Sugestões de FAQ extraídas de conversas resolvidas por um agente Autonom.ia (#284 · Entrega 2b).
  # Só a tabela (transacional). Os índices vão em migration própria, CONCURRENTLY (padrão 20260903140100).
  # conversation_id/reviewed_by_id são FKs lógicas (sem constraint): a sugestão sobrevive à conversa/usuário.
  def change
    create_table :autonomia_agent_faq_suggestions do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :autonomia_agent, null: false, index: false,
                                     foreign_key: { to_table: :autonomia_agents, on_delete: :cascade }
      t.bigint :conversation_id
      t.text :question, null: false
      t.text :answer, null: false
      t.integer :status, null: false, default: 0 # pending:0 approved:1 edited:2 ignored:3
      t.bigint :reviewed_by_id
      t.datetime :reviewed_at
      t.jsonb :source_message_ids, null: false, default: []
      t.string :question_hash, null: false # SHA256 da pergunta normalizada (dedupe)

      t.timestamps
    end
  end
end
