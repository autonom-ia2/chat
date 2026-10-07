# Importar modelo de e-mail (#1099, entrega D): quantos trechos a IA já refez por conta em cada mês, para o teto mensal.
# Uma linha por conta e mês, somada com um único INSERT ... ON CONFLICT condicional (a contagem é atômica mesmo com
# dois cliques ao mesmo tempo). Tabela própria do fork.
class CreateEmailTemplateImportAiQuotas < ActiveRecord::Migration[7.2]
  def change
    create_table :email_template_import_ai_quotas do |t|
      t.bigint :account_id, null: false
      t.date :period, null: false
      t.integer :used, null: false, default: 0
      t.timestamps
    end
    add_index :email_template_import_ai_quotas, [:account_id, :period], unique: true, name: 'index_email_import_ai_quotas_on_account_and_period'
    add_foreign_key :email_template_import_ai_quotas, :accounts, on_delete: :cascade
  end
end
