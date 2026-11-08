# IA cuida dos comentários (#2454): "O que eu vi na foto" de um post (Crm::MetaAds::ComentariosIa::Foto). Uma linha por
# post: a descrição que a IA escreveu e, quando o dono corrigiu, a correção, que vale no lugar dela.
class Crm::MetaAdsPostReading < ApplicationRecord
  self.table_name = 'crm_meta_ads_post_readings'

  NETWORKS = %w[instagram facebook].freeze
  TEXT_LIMIT = 1000

  belongs_to :account
  belongs_to :corrected_by, class_name: 'User', optional: true

  validates :network, inclusion: { in: NETWORKS }
  validates :post_id, presence: true, uniqueness: { scope: [:account_id, :network] }
  validates :description, :correction, length: { maximum: TEXT_LIMIT }

  # O que vai à IA: a correção do dono, quando existe; senão, a descrição.
  def texto_para_ia
    correction.presence || description.presence
  end
end
