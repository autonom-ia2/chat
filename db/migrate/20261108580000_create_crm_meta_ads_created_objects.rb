# #2198 — o que a plataforma criou na Meta pelo "Anúncio novo" (e, depois, impulsionar, duplicar e criar post).
#
# Uma linha por tentativa de criar, com a chave de idempotência da tela: dois toques no botão, ou nova tentativa depois
# de timeout, acham a mesma linha e não criam duas campanhas. Guarda os ids da campanha, do grupo, do criativo e do
# anúncio, para desfazer o começo quando um passo falha e para listar os anúncios criados aqui que seguem pausados
# ("Pausados, esperando você ativar"). O orçamento e as datas de quando criou ficam em `budget`, para essa lista não ler
# o orçamento de cada anúncio na Meta. Tabela nova: nada existente muda.
class CreateCrmMetaAdsCreatedObjects < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ads_created_objects do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :user_id
      t.string :kind, null: false, default: 'ad'
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: 'creating'
      t.string :name, limit: 255
      t.string :ad_account_id
      t.string :campaign_id
      t.string :adset_id
      t.string :creative_id
      t.string :ad_id
      t.jsonb :budget, null: false, default: {}
      t.string :error_code
      t.datetime :activated_at
      t.timestamps
    end
    add_index :crm_meta_ads_created_objects, [:account_id, :idempotency_key], unique: true, name: 'idx_crm_meta_ads_created_objects_key'
    add_index :crm_meta_ads_created_objects, [:account_id, :ad_id], name: 'idx_crm_meta_ads_created_objects_ad'
  end
end
