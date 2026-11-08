# IA cuida dos comentários (#2212): o começo da mensagem do privado escrito pela IA a partir da legenda do post
# (Crm::MetaAds::ComentariosIa::Rascunho). Guardado com o digest da legenda: a mesma legenda não chama a IA de novo.
class Crm::MetaAdsCommentDraft < ApplicationRecord
  self.table_name = 'crm_meta_ads_comment_drafts'

  STATUSES = %w[writing ready no_offer invalid failed].freeze

  belongs_to :account

  validates :status, inclusion: { in: STATUSES }
end
