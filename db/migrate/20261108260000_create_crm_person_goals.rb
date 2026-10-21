# Meta do mês por pessoa em CRM › Números (#1991, F4 do #1871). Uma linha por funil de Vender, pessoa e mês, em centavos
# na moeda do funil. Sem linha = sem meta. A meta do funil continua em crm_pipelines.metadata['goals'].
class CreateCrmPersonGoals < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_person_goals do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines, on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      # O primeiro dia do mês, no fuso da conta.
      t.date :month, null: false
      t.bigint :target_cents, null: false
      t.string :currency, null: false, default: 'BRL'
      t.timestamps

      t.index %i[pipeline_id user_id month], unique: true, name: 'idx_crm_person_goals_unique'
      t.index %i[account_id month], name: 'idx_crm_person_goals_account_month'
      t.index :user_id
    end
  end
end
