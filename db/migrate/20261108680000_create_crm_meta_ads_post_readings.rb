# #2454 — IA cuida dos comentários: "O que eu vi na foto". Uma leitura por post (Instagram ou Facebook), feita pela IA
# só depois do clique do dono em "Cuidar dos comentários", e a correção do dono, que vale no lugar da leitura. A leitura
# existe antes de haver cuidado, por isso tem tabela própria (não cabe em crm_meta_ads_comment_cares).
class CreateCrmMetaAdsPostReadings < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ads_post_readings do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :network, null: false
      t.string :post_id, null: false
      # O que a IA viu na foto (ou nas fotos do carrossel), em poucas linhas.
      t.text :description
      # O texto do dono, quando ele corrigiu a leitura.
      t.text :correction
      t.references :corrected_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :model
      t.datetime :read_at
      t.timestamps
      t.index [:account_id, :network, :post_id], unique: true, name: 'idx_crm_meta_ads_post_readings_post'
    end
  end
end
