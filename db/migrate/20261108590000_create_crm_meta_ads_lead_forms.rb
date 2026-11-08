# #2195 — quem preenche o formulário instantâneo do anúncio da Meta vira card no funil e na etapa escolhidos para aquele
# formulário. Duas tabelas novas, nenhuma alteração em tabela existente (a das Páginas, crm_meta_ads_pages, veio no
# #2264):
# - crm_meta_ads_lead_forms: o destino de cada formulário (funil e etapa) e o que já foi trazido dos últimos 90 dias.
# - crm_meta_ads_leads: cada lead que entrou, um por leadgen_id, para o webhook repetido não criar card duas vezes.
# Nenhum token fica aqui: o token da Página sai na hora do token do cliente (Crm::MetaAdsConnection).
class CreateCrmMetaAdsLeadForms < ActiveRecord::Migration[7.2]
  def change
    create_lead_forms
    create_leads
  end

  private

  def create_lead_forms
    create_table :crm_meta_ads_lead_forms do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :page_id, null: false
      t.string :form_id, null: false
      t.string :form_name, limit: 255
      t.references :pipeline, foreign_key: { to_table: :crm_pipelines, on_delete: :nullify }
      t.references :stage, foreign_key: { to_table: :crm_pipeline_stages, on_delete: :nullify }
      t.integer :brought_count
      t.references :brought_pipeline, foreign_key: { to_table: :crm_pipelines, on_delete: :nullify }
      t.references :brought_stage, foreign_key: { to_table: :crm_pipeline_stages, on_delete: :nullify }
      t.timestamps
    end
    add_index :crm_meta_ads_lead_forms, [:account_id, :form_id], unique: true
  end

  # contact_id e card_id com índice: apagar contato ou card faz o nullify sem varrer a tabela.
  def create_leads
    create_table :crm_meta_ads_leads do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :leadgen_id, null: false
      t.string :page_id
      t.string :form_id
      t.string :ad_id
      t.string :ad_name, limit: 255
      t.string :campaign_name, limit: 255
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.references :card, foreign_key: { to_table: :crm_cards, on_delete: :nullify }
      t.boolean :new_contact, null: false, default: false
      t.datetime :received_at, null: false
      t.timestamps
    end
    add_index :crm_meta_ads_leads, [:account_id, :leadgen_id], unique: true
    add_index :crm_meta_ads_leads, [:account_id, :received_at]
    add_index :crm_meta_ads_leads, [:account_id, :form_id, :received_at]
  end
end
