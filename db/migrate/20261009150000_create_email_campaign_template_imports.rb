# Importar modelo de e-mail (#1099, entrega B): uma importação por pedido, com o estado do job, o relatório que a tela
# lê, o MJML resultante e a trava que garante uma importação ativa por conta. Tabela própria do fork; as imagens e a
# entrada recebida ficam como anexos do ActiveStorage, sem coluna em tabela do upstream.
class CreateEmailCampaignTemplateImports < ActiveRecord::Migration[7.2]
  def change
    create_imports_table
    add_imports_indexes
    add_foreign_key :email_campaign_template_imports, :accounts, on_delete: :cascade
    add_foreign_key :email_campaign_template_imports, :email_campaign_templates, on_delete: :nullify
  end

  private

  def create_imports_table
    create_table :email_campaign_template_imports do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.string :status, null: false, default: 'queued'
      t.string :source_kind, null: false
      t.string :source_url
      t.jsonb :report, null: false, default: {}
      t.jsonb :blocking, null: false, default: []
      t.text :result_mjml
      t.string :error_code
      t.integer :attempts, null: false, default: 0
      t.datetime :locked_until
      t.datetime :expires_at, null: false
      t.bigint :email_campaign_template_id
      t.timestamps
    end
  end

  def add_imports_indexes
    add_index :email_campaign_template_imports, [:account_id, :created_at], name: 'index_email_template_imports_on_account_and_created'
    add_index :email_campaign_template_imports, :account_id, unique: true, where: "status IN ('queued', 'processing')",
                                                             name: 'index_email_template_imports_one_active_per_account'
    add_index :email_campaign_template_imports, :expires_at
    add_index :email_campaign_template_imports, :email_campaign_template_id, name: 'index_email_template_imports_on_template'
  end
end
