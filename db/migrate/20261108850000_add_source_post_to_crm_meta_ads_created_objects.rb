# #2522 (item 3) — o post de origem do anúncio que a plataforma cria ao impulsionar um post.
#
# Com ele, Seus posts marca "Teve anúncio" no post impulsionado por aqui (no Instagram a Meta não diz) e o detalhe do
# post leva aos comentários do anúncio, que no Instagram ficam noutra mídia (effective_instagram_media_id). Anúncio
# com criativo novo, sem post, fica com as duas colunas nulas, como todas as linhas que já existem. Só colunas novas e
# um índice novo: nada existente muda. O índice entra sem travar as escritas (concurrently), fora de transação; por
# isso cada passo pode rodar de novo sem erro se o deploy cair no meio.
class AddSourcePostToCrmMetaAdsCreatedObjects < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_column :crm_meta_ads_created_objects, :source_post_id, :string, if_not_exists: true
    add_column :crm_meta_ads_created_objects, :source_post_network, :string, if_not_exists: true
    add_index :crm_meta_ads_created_objects, [:account_id, :source_post_id],
              name: 'idx_crm_meta_ads_created_objects_source_post', algorithm: :concurrently, if_not_exists: true
  end
end
