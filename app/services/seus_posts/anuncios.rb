# Os anúncios de um post do Instagram em Seus posts (#2522, #2739, #2804): o post impulsionado por aqui vira anúncios
# cujos comentários ficam noutra mídia, e o post leva a cada um (o anúncio por dentro, em Anúncios da Meta).
#
# - `ligados?`: Anúncios da Meta e os comentários do Instagram no anúncio ligados na conta. Sem eles, o post não lê nem
#   mostra os comentários do anúncio.
# - `visiveis?`: e quem vê pode abrir Anúncios da Meta (Crm::MetaAdsConnectionPolicy#show?). Sem isso, o atalho não
#   aparece e os comentários do anúncio não entram no "Esperando você" dessa pessoa: ela não teria como chegar a eles.
# - `conta_de_anuncios`: a conta de anúncios conectada agora. Só os anúncios dela: o detalhe não abre o de outra conta.
module SeusPosts::Anuncios
  FLAGS = %w[meta_ads_hub meta_ads_comentarios_instagram].freeze

  def self.ligados?(account)
    FLAGS.all? { |flag| account.feature_enabled?(flag) }
  end

  def self.visiveis?(account, viewer)
    ligados?(account) && Pundit.policy!(viewer, ::Crm::MetaAdsConnection).show?
  end

  def self.conta_de_anuncios(account_id)
    ::Crm::MetaAdsConnection.active_for(account_id)&.ad_account_id.presence
  end
end
