# Ponte anúncio → landing page → WhatsApp (#1011). Aditiva, só tabelas do fork.
#
# Um link passa a ter dois usos: `direct` (QR/link, como sempre foi) e `website`
# (botão de uma página que avisa o clique em paralelo, POST /l/:code/clicks).
# O clique da página guarda a campanha, a URL da página, os dados do formulário e,
# com consentimento de marketing, os sinais da Meta (fbc/fbp/IP/user agent).
class AddWebsiteAttributionToCtwaTrackedLinks < ActiveRecord::Migration[7.1]
  def change
    change_table :ctwa_tracked_links, bulk: true do |t|
      t.string :usage, null: false, default: 'direct'
      t.jsonb :allowed_origins, null: false, default: []
      t.datetime :last_signal_at
    end

    change_table :ctwa_tracked_link_clicks, bulk: true do |t|
      t.string :campaign_key
      t.string :page_url, limit: 512
      t.jsonb :lead_data, null: false, default: {}
      t.jsonb :meta_signals, null: false, default: {}
    end

    add_index :ctwa_tracked_link_clicks, [:tracked_link_id, :campaign_key], name: 'idx_ctwa_tracked_link_clicks_link_campaign'
  end
end
