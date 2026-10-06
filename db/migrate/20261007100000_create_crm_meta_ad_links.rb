# Anúncios da Meta F2b (#1073). Aditiva, só tabela do fork.
#
# Cada toque de anúncio da Meta numa conversa vira uma linha: qual anúncio, conjunto e campanha, por onde veio
# (WhatsApp direto ou página do site) e o quanto sabemos (`certainty`). O card sai da conversa pelas ligações do
# CRM (crm_card_conversations), sem copiar aqui. Regravar o mesmo toque atualiza a linha, nunca duplica.
class CreateCrmMetaAdLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_meta_ad_links do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :touch_key, null: false
      t.string :ad_account_id
      t.string :ad_id
      t.string :adset_id
      t.string :campaign_id
      t.string :origin, null: false
      t.string :certainty, null: false
      t.boolean :first_touch, null: false, default: false
      t.datetime :touched_at, null: false
      t.timestamps
    end
    add_index :crm_meta_ad_links, [:conversation_id, :touch_key], unique: true, name: 'idx_crm_meta_ad_links_unique'
    add_index :crm_meta_ad_links, [:account_id, :touched_at], name: 'idx_crm_meta_ad_links_account_touched'
    add_index :crm_meta_ad_links, [:account_id, :ad_id], name: 'idx_crm_meta_ad_links_account_ad'

    # Fim da carga das ligações dos últimos 90 dias.
    add_column :crm_meta_ads_connections, :links_backfilled_at, :datetime
  end
end
