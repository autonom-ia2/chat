# Multifunil 8/11 (#1148): acesso por funil, por pessoa e por caixa (R2–R5). Sem linha, nada muda: a pessoa vê o que
# vê hoje (R5). A tela que grava estas linhas é a #1149.
# - all_pipelines: vê as conversas de todos os funis da caixa; falso = só os funis em crm_inbox_agent_pipelines.
# - triage: vê as conversas ainda sem card (triagem, R3).
# - only_own: "Só as suas" — só as atribuídas a ela ou em que participa (R4). Atribuído e participante sempre veem.
class CreateCrmInboxAgentAccesses < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_inbox_agent_accesses do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.boolean :all_pipelines, null: false, default: true
      t.boolean :triage, null: false, default: true
      t.boolean :only_own, null: false, default: false
      t.timestamps
    end
    add_index :crm_inbox_agent_accesses, [:account_id, :user_id, :inbox_id], unique: true, name: 'idx_crm_inbox_agent_accesses_unique'
    add_index :crm_inbox_agent_accesses, [:inbox_id], name: 'idx_crm_inbox_agent_accesses_inbox'

    create_table :crm_inbox_agent_pipelines do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :access, null: false, foreign_key: { to_table: :crm_inbox_agent_accesses, on_delete: :cascade }, index: false
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines, on_delete: :cascade }, index: true
      t.timestamps
    end
    add_index :crm_inbox_agent_pipelines, [:access_id, :pipeline_id], unique: true, name: 'idx_crm_inbox_agent_pipelines_unique'
  end
end
