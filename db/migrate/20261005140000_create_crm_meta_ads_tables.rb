# Nomes das campanhas da Meta (#1034). Aditiva, só tabelas do fork.
#
# `crm_meta_ads_connections`: uma credencial de leitura de anúncios (ads_read) por conta,
# com o token cifrado pelo ActiveRecord::Encryption. `crm_meta_ad_objects`: cache dos nomes de
# anúncio, conjunto e campanha que a Graph API devolve para os IDs dos parâmetros automáticos.
class CreateCrmMetaAdsTables < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_meta_ads_connections do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :access_token, null: false
      t.string :status, null: false, default: 'active'
      t.datetime :last_checked_at
      t.string :last_error, limit: 255
      t.timestamps
    end

    create_table :crm_meta_ad_objects do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :meta_object_id, null: false
      t.string :object_type
      t.string :name, limit: 255
      t.string :campaign_id
      t.string :adset_id
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :crm_meta_ad_objects, [:account_id, :meta_object_id], unique: true, name: 'idx_crm_meta_ad_objects_account_object'
  end
end
