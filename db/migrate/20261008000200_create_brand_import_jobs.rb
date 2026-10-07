# Importação da identidade visual a partir do site (#1076). Tabela do fork (aditiva). O resultado é a
# proposta já extraída (cores, fontes, logo candidata, redes, rodapé) — nunca HTML/CSS bruto.
# No máximo uma importação na fila ou rodando por conta (status 0 = queued, 1 = running).
class CreateBrandImportJobs < ActiveRecord::Migration[7.2]
  def change
    create_table :brand_import_jobs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :url, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :result
      t.string :error_code
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :brand_import_jobs, :account_id, unique: true, where: 'status IN (0, 1)',
                                               name: 'idx_brand_import_jobs_one_active_per_account'
    add_index :brand_import_jobs, [:account_id, :created_at]
  end
end
