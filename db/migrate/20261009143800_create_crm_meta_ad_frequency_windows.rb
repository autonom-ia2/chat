# Anúncios da Meta F5 (#1110, D5.4). Aditiva, só tabela do fork.
#
# Frequência de cada anúncio numa janela de dias (hoje, 7), lida da Meta numa consulta sem `time_increment`.
# Alcance não soma entre dias, então a frequência diária de crm_meta_ad_insights_daily não dá a da semana.
# `date_end` é o `date_stop` que a Meta devolveu, nunca "ontem" calculado aqui. Reler a mesma janela sobrescreve.
class CreateCrmMetaAdFrequencyWindows < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ad_frequency_windows do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :ad_account_id, null: false
      t.string :ad_id, null: false
      t.string :adset_id
      t.integer :window_days, limit: 2, null: false
      t.date :date_end, null: false
      t.bigint :impressions, :reach, null: false, default: 0
      t.decimal :frequency, precision: 10, scale: 4
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :crm_meta_ad_frequency_windows, [:account_id, :ad_account_id, :ad_id, :window_days, :date_end],
              unique: true, name: 'idx_crm_meta_ad_freq_windows_unique'
  end
end
