# O que já foi feito num comentário de anúncio da Meta (#2196), nas duas redes. A Meta não diz se um comentário já
# recebeu a resposta no privado (Private Reply, uma só por comentário): sem esta linha o botão voltaria depois de
# enviar e a tela não saberia abrir a conversa. O comentário em si não é gravado (dado de terceiro, lido ao vivo).
# Quem grava: o painel (#2196 Instagram, #2197 Facebook) e a IA dos comentários (#2212).
#
# Só as ações que acontecem uma vez por comentário são únicas (a linha é a reivindicação, gravada antes de chamar a
# Meta): a resposta no privado e a leitura da IA. Responder, ocultar e mostrar podem se repetir. `attempted_at`: quando a
# chamada do privado saiu; `failed_at`: quando a resposta se perdeu; `confirmed_at`: quando a Meta o confirmou (estados
# em docs/meta/comentarios-instagram.md).
class CreateCrmMetaAdsCommentActions < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ads_comment_actions do |t|
      t.references :account, null: false, index: false, foreign_key: true
      t.string :network, null: false
      t.string :ad_id
      t.string :comment_id, null: false
      t.string :action, null: false
      t.references :conversation, index: { name: 'idx_crm_meta_ads_comment_actions_conversation' }, foreign_key: { on_delete: :nullify }
      t.string :actor, null: false
      t.references :user, index: { name: 'idx_crm_meta_ads_comment_actions_user' }, foreign_key: { on_delete: :nullify }
      t.datetime :at, null: false
      t.datetime :attempted_at
      t.datetime :failed_at
      t.datetime :confirmed_at
      t.timestamps
    end
    # action::text: com o cast escrito, o Postgres devolve a mesma condição quando o schema.rb é carregado de novo
    # (sem ele, o IN em varchar volta em outra forma e o schema.rb nunca bate com a migration).
    add_index :crm_meta_ads_comment_actions, [:network, :comment_id, :action], unique: true,
                                                                               where: "action::text IN ('private_reply', 'ai_seen')",
                                                                               name: 'idx_crm_meta_ads_comment_actions_once'
    add_index :crm_meta_ads_comment_actions, [:account_id, :network, :comment_id], name: 'idx_crm_meta_ads_comment_actions_lookup'
  end
end
