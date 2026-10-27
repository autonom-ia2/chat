# Páginas do Facebook de cada conta (#2195, comum ao #2197). O webhook de Página (leadgen dos formulários, feed dos
# comentários) chega só com o page_id: esta tabela diz de que conta, ou contas, ela é. A mesma Página pode estar em mais
# de uma conta. Cada frente guarda aqui se assinou o seu campo na Página: `leadgen_receiving` (#2195) e `feed_receiving`
# (#2197). Nenhum token fica aqui: o da Página sai na hora do token do cliente (Crm::MetaAdsConnection).
class CreateCrmMetaAdsPages < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ads_pages do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :page_id, null: false
      t.string :name, limit: 255
      t.boolean :leadgen_receiving, null: false, default: false
      t.boolean :feed_receiving, null: false, default: false
      t.timestamps
    end
    add_index :crm_meta_ads_pages, [:account_id, :page_id], unique: true
    add_index :crm_meta_ads_pages, :page_id
  end
end
