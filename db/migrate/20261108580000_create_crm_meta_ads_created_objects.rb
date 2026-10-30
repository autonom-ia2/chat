# #2198 — o que a plataforma criou na Meta pelo "Anúncio novo" (e, depois, impulsionar, duplicar e criar post).
#
# Uma linha por tentativa de criar, com a chave de idempotência da tela: dois toques no botão, ou nova tentativa depois
# de timeout, acham a mesma linha e não criam duas campanhas. Guarda os ids da campanha, do grupo, do criativo e do
# anúncio, para desfazer o começo quando um passo falha e para listar os anúncios criados aqui que seguem pausados
# ("Pausados, esperando você ativar"). O orçamento e as datas de quando criou ficam em `budget`, para essa lista não ler
# o orçamento de cada anúncio na Meta. Tabela nova: nada existente muda.
class CreateCrmMetaAdsCreatedObjects < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meta_ads_created_objects do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :user_id
      t.string :kind, null: false, default: 'ad'
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: 'creating'
      t.string :name, limit: 255
      t.string :ad_account_id
      t.string :campaign_id, :adset_id, :creative_id, :ad_id
      t.jsonb :budget, null: false, default: {}
      t.string :error_code
      # `switching_at`: trava do "Ativar"/"Pausar" de um anúncio criado aqui. Enquanto liga ou pausa os três níveis, um
      # segundo clique recebe in_progress (Crm::MetaAds::Creation::Activation).
      t.datetime :activated_at, :switching_at
      # SHA-256 do pedido validado (Crm::MetaAds::Creation::Draft#digest): o mesmo pedido com outra chave (outra aba,
      # outro aparelho, a tela reaberta) não cria a segunda campanha enquanto houver uma tentativa dele que ainda pode
      # ter campanha viva na Meta. O índice único parcial abaixo é a trava: dois pedidos iguais no mesmo instante não
      # passam os dois.
      t.string :request_digest, limit: 64
      t.timestamps
    end
    add_indexes
  end

  private

  def add_indexes
    add_index :crm_meta_ads_created_objects, [:account_id, :idempotency_key], unique: true, name: 'idx_crm_meta_ads_created_objects_key'
    add_index :crm_meta_ads_created_objects, [:account_id, :ad_id], name: 'idx_crm_meta_ads_created_objects_ad'
    add_index :crm_meta_ads_created_objects, [:account_id, :ad_account_id, :request_digest],
              unique: true, name: 'idx_crm_meta_ads_created_objects_digest',
              where: "((status)::text = ANY (ARRAY[('creating'::character varying)::text, " \
                     "('unconfirmed'::character varying)::text, ('rollback_failed'::character varying)::text]))"
  end
end
