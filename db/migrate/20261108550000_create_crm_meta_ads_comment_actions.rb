# O que já foi feito num comentário de anúncio da Meta (#2196), nas duas redes. A Meta não diz se um comentário já
# recebeu a resposta no privado (Private Reply, uma só por comentário): sem esta linha o botão voltaria depois de
# enviar e a tela não saberia abrir a conversa. O comentário em si não é gravado (dado de terceiro, lido ao vivo).
# Quem grava: o painel (#2196 Instagram, #2197 Facebook) e a IA dos comentários (#2212).
class CreateCrmMetaAdsCommentActions < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ads_comment_actions do |t|
      t.references :account, null: false, index: false
      t.string :network, null: false
      t.string :comment_id, null: false
      t.string :action, null: false
      t.bigint :conversation_id
      t.string :actor, null: false
      t.bigint :user_id
      t.datetime :at, null: false
      t.timestamps
    end
    add_index :crm_meta_ads_comment_actions, [:network, :comment_id, :action], unique: true,
                                                                               name: 'idx_crm_meta_ads_comment_actions_unique'
    add_index :crm_meta_ads_comment_actions, [:account_id, :network, :comment_id], name: 'idx_crm_meta_ads_comment_actions_lookup'
  end
end
