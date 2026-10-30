# #2212 — o começo da mensagem do privado que a IA escreve a partir da legenda do post (passo 1 do cuidado). Um por
# post, com o digest da legenda: abrir a tela de novo com a mesma legenda não chama a IA; só uma legenda nova chama.
# `status`: writing (reservado antes de chamar a IA: duas aberturas juntas fazem uma chamada só), ready, no_offer (o
# post não oferece nada), invalid (a resposta não serviu) ou failed (a IA não respondeu; tenta de novo mais tarde).
class CreateCrmMetaAdsCommentDrafts < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ads_comment_drafts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :target_kind, null: false
      t.string :target_id, null: false
      t.string :caption_digest, null: false
      t.string :status, null: false
      t.text :message
      t.timestamps
      t.index [:account_id, :target_kind, :target_id], unique: true, name: 'idx_crm_meta_ads_comment_drafts_target'
    end
  end
end
