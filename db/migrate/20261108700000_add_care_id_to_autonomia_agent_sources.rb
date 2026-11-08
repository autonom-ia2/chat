# #2487 (PR 3b do #2436): o material só de um post ou anúncio. A fonte com `care_id` é do cuidado dos comentários
# (Crm::MetaAdsCommentCare), não do agente: só a resposta a um comentário daquele cuidado lê. A coluna é nula em todas as
# fontes de hoje, que continuam do agente.
#
# Sem transação: o índice entra com CONCURRENTLY (parcial, só as fontes de um cuidado). A chave estrangeira entra sem
# validar (a coluna nasce vazia) e o CASCADE é só a rede de segurança: quem apaga o material é o `dependent: :destroy` do
# cuidado, que leva os trechos e o arquivo junto.
class AddCareIdToAutonomiaAgentSources < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    add_column :autonomia_agent_sources, :care_id, :bigint unless column_exists?(:autonomia_agent_sources, :care_id)
    add_index :autonomia_agent_sources, :care_id, where: 'care_id IS NOT NULL', algorithm: :concurrently, if_not_exists: true
    return if foreign_key_exists?(:autonomia_agent_sources, :crm_meta_ads_comment_cares, column: :care_id)

    add_foreign_key :autonomia_agent_sources, :crm_meta_ads_comment_cares, column: :care_id, on_delete: :cascade, validate: false
  end

  def down
    remove_foreign_key :autonomia_agent_sources, :crm_meta_ads_comment_cares, column: :care_id, if_exists: true
    remove_index :autonomia_agent_sources, :care_id, algorithm: :concurrently, if_exists: true
    remove_column :autonomia_agent_sources, :care_id, if_exists: true
  end
end
