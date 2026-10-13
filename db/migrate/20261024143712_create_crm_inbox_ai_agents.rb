# Agente de IA responsável por caixa + funil (#1447): na caixa X, o funil Y é atendido pelo agente Z. Uma linha por par
# caixa/funil. Sem linha, nada muda: quem atende segue sendo a porta (o robô ativo da caixa).
class CreateCrmInboxAiAgents < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_inbox_ai_agents do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines, on_delete: :cascade }, index: true
      t.references :autonomia_agent, null: false, foreign_key: { to_table: :autonomia_agents, on_delete: :cascade }, index: true
      t.timestamps
    end
    add_index :crm_inbox_ai_agents, [:inbox_id, :pipeline_id], unique: true, name: 'idx_crm_inbox_ai_agents_unique'
  end
end
