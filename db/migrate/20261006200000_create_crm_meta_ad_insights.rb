# Anúncios da Meta F2a (#1073). Aditiva, só tabelas do fork.
#
# Gasto e resultado de cada anúncio, um dia por linha, lidos da Insights API da Meta. Reler um dia
# sobrescreve a linha (a Meta corrige números de até 28 dias atrás), nunca duplica. O posicionamento
# (Feed, Stories, Reels…) fica numa tabela própria, lida só na carga diária.
#
# Os valores ficam na moeda e no fuso da conta de anúncios, como a Meta os entrega: sem conversão.
class CreateCrmMetaAdInsights < ActiveRecord::Migration[7.1]
  def change
    create_insights_daily
    create_placements_daily

    # Última leitura do dia de hoje, fim da primeira carga de 90 dias e fuso da conta de anúncios (o "hoje" da
    # Meta é o dela, não o de quem abre a tela).
    change_table :crm_meta_ads_connections, bulk: true do |t|
      t.datetime :insights_synced_at
      t.datetime :insights_backfilled_at
      t.string :ad_account_timezone
    end
  end

  private

  def create_insights_daily
    create_table :crm_meta_ad_insights_daily do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :ad_account_id, null: false
      t.string :ad_id, null: false
      t.string :adset_id
      t.string :campaign_id
      t.date :date, null: false
      t.string :currency, limit: 3
      t.decimal :spend, precision: 14, scale: 2, null: false, default: 0
      t.bigint :impressions, :reach, :link_clicks, null: false, default: 0
      t.decimal :frequency, precision: 10, scale: 4
      t.integer :conversations_started, null: false, default: 0
      t.jsonb :actions, null: false, default: []
      t.string :attribution_window, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    index_insights_daily
  end

  def index_insights_daily
    add_index :crm_meta_ad_insights_daily, [:account_id, :ad_account_id, :ad_id, :date],
              unique: true, name: 'idx_crm_meta_ad_insights_daily_unique'
    add_index :crm_meta_ad_insights_daily, [:account_id, :date], name: 'idx_crm_meta_ad_insights_daily_account_date'
  end

  def create_placements_daily
    create_table :crm_meta_ad_placements_daily do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :ad_account_id, null: false
      t.string :ad_id, null: false
      t.date :date, null: false
      t.string :publisher_platform, null: false
      t.string :platform_position, null: false
      t.decimal :spend, precision: 14, scale: 2, null: false, default: 0
      t.bigint :impressions, null: false, default: 0
      t.bigint :link_clicks, null: false, default: 0
      t.integer :conversations_started, null: false, default: 0
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :crm_meta_ad_placements_daily, [:account_id, :ad_account_id, :ad_id, :date, :publisher_platform, :platform_position],
              unique: true, name: 'idx_crm_meta_ad_placements_daily_unique'
  end
end
