# #2212 — IA cuida dos comentários: o cuidado de cada post ou anúncio. O que a IA fez com cada comentário fica em
# crm_meta_ads_comment_actions (#2196); o comentário em si não é gravado (dado de terceiro, lido ao vivo).
class CreateCrmMetaAdsCommentCares < ActiveRecord::Migration[7.2]
  def change # rubocop:disable Metrics/MethodLength -- uma tabela, uma coluna por linha
    create_table :crm_meta_ads_comment_cares do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :target_kind, null: false
      t.string :target_id, null: false
      # No anúncio, os posts do criativo (Facebook: effective_object_story_id; Instagram: a mídia), por onde chega o comentário.
      t.jsonb :post_ids, null: false, default: []
      t.string :network, null: false
      t.string :status, null: false, default: 'on'
      t.jsonb :offer
      t.text :note
      t.text :message, null: false
      # Para quem vai o privado, nas palavras do dono (#2306, opção a): a IA decide comentário a comentário se é o caso.
      t.text :para_quem
      t.jsonb :button
      t.jsonb :phrases, null: false, default: []
      t.text :price_reply
      t.string :handoff, null: false, default: 'assignment'
      # Quando o dono mandou ler os comentários que chegaram antes de ligar ("Ler e mandar"): uma vez por cuidado.
      t.datetime :read_old_at
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :started_at, null: false
      t.timestamps
      t.index [:account_id, :target_kind, :target_id], unique: true, name: 'idx_crm_meta_ads_comment_cares_target'
      t.index :post_ids, using: :gin
    end
  end
end
