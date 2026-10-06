# Anúncios da Meta F1 (#1047). Aditiva, só tabela do fork.
#
# A conexão passa a ter dois modos: `token` (o cliente cola um token, como em #1034) e `partner` (o cliente
# compartilha a conta de anúncios com o portfólio da plataforma e a leitura usa o token da plataforma). No
# modo `partner` não há token por conta, por isso `access_token` deixa de ser obrigatório no banco; o model
# segue exigindo token no modo `token`.
class AddSetupToCrmMetaAdsConnections < ActiveRecord::Migration[7.1]
  def change
    change_column_null :crm_meta_ads_connections, :access_token, true

    change_table :crm_meta_ads_connections, bulk: true do |t|
      t.string :mode, null: false, default: 'token'
      t.string :ad_account_id
      t.string :ad_account_name, limit: 255
      t.string :ad_account_business_id
      t.string :pixel_id
      t.string :pixel_name, limit: 255
      t.jsonb :destinations, null: false, default: {}
      t.datetime :verified_at
    end

    # Prévia e miniatura do anúncio, para o botão "Ver anúncio" do card (CA-1.11).
    change_table :crm_meta_ad_objects, bulk: true do |t|
      t.text :preview_url
      t.text :thumbnail_url
    end

    # Uma conta de anúncios lida pela plataforma pertence a uma única conta do Chat2You.
    add_index :crm_meta_ads_connections, :ad_account_id,
              unique: true, where: "mode = 'partner'", name: 'idx_crm_meta_ads_connections_partner_ad_account'
  end
end
