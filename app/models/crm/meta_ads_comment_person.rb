# IA cuida dos comentários (#2212): um privado por pessoa em cada post. A Meta não diz se o Private Reply é um por
# comentário ou por pessoa; até a chamada real dizer, a mesma pessoa comentando de novo não recebe outro privado.
#
# A linha é reservada ANTES de chamar a Meta (índice único em conta, rede, post e quem comentou): dois comentários da
# mesma pessoa em jobs ao mesmo tempo não levam dois privados, e a marca não depende de a conversa ter sido gravada
# depois do envio. Recusa da Meta (4xx): a linha sai, e o próximo comentário da pessoa pode receber. Sem confirmação (a
# Meta pode ter entregado): a linha fica.
class Crm::MetaAdsCommentPerson < ApplicationRecord
  self.table_name = 'crm_meta_ads_comment_people'

  belongs_to :account

  validates :network, :post_id, :from_id, :comment_id, presence: true
end
