class AddScoreIndexToCrmCards < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # Sem este índice, a ordenação por score do Kanban/lista e a varredura periódica do
  # ScoreDecayJob (pipeline + status + score > 0) caem em scan sequencial conforme a base cresce.
  def change
    add_index :crm_cards, [:pipeline_id, :status, :score],
              name: 'index_crm_cards_on_pipeline_status_score', algorithm: :concurrently
    add_index :crm_cards, [:account_id, :score, :updated_at],
              name: 'index_crm_cards_on_account_score_updated', algorithm: :concurrently
  end
end
