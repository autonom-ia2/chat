# #2212 — o começo da mensagem do privado que a IA escreve a partir da legenda do post (passo 1 do cuidado). Um por
# post, com o digest da legenda: abrir a tela de novo com a mesma legenda não chama a IA; só uma legenda nova chama.
# `message` nulo: a IA leu e o post não oferece nada (o campo fica vazio, sem perguntar de novo).
class CreateCrmMetaAdsCommentDrafts < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ads_comment_drafts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :target_kind, null: false
      t.string :target_id, null: false
      t.string :caption_digest, null: false
      t.text :message
      t.timestamps
      t.index [:account_id, :target_kind, :target_id], unique: true, name: 'idx_crm_meta_ads_comment_drafts_target'
    end
  end
end
