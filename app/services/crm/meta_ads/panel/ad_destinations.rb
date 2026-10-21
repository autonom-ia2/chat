# Para onde cada anúncio leva (#2054), pelo `destination_type` do conjunto que a Meta manda (Crm::MetaAds::Insights::Destinations).
#
# Só afirma "não leva a uma conversa" quando a Meta disse um destino que está em OUTSIDE (site, app, vídeo, perfil…).
# Sem o destino — conjunto ainda não lido (Insights::Destinations), UNDEFINED ou um valor novo da Meta — não afirma
# nada: o anúncio segue entre os que trazem conversa, como um anúncio novo de WhatsApp sem a primeira mensagem.
class Crm::MetaAds::Panel::AdDestinations
  # Os destinos que não são de mensagem, da referência do conjunto de anúncios (Marketing API, destination_type,
  # conferida em 21/10/2026). Os de mensagem (WHATSAPP, MESSENGER, INSTAGRAM_DIRECT e os MESSAGING_*) ficam de fora.
  OUTSIDE = %w[
    WEBSITE APP APPLINKS_AUTOMATIC FACEBOOK SHOP_AUTOMATIC ON_AD ON_POST ON_EVENT ON_VIDEO ON_PAGE INSTAGRAM_PROFILE
    FACEBOOK_PAGE INSTAGRAM_PROFILE_AND_FACEBOOK_PAGE INSTAGRAM_LIVE FACEBOOK_LIVE IMAGINE
  ].freeze
  UNDEFINED = 'UNDEFINED'.freeze

  # insights: as linhas de gasto do período (trazem o conjunto de cada anúncio).
  def initialize(account_id, insights)
    @account_id = account_id
    @insights = insights
  end

  def outside_conversation?(ad_id)
    OUTSIDE.include?(destinations[adsets[ad_id]])
  end

  private

  # Conjunto de cada anúncio: o do cache de nomes e, enquanto o anúncio não foi resolvido, o que veio no gasto.
  def adsets
    @adsets ||= begin
      from_spend = @insights.where.not(adset_id: nil).distinct.pluck(:ad_id, :adset_id).to_h
      cached = Crm::MetaAdObject.where(account_id: @account_id, meta_object_id: @insights.distinct.pluck(:ad_id))
                                .where.not(adset_id: nil).pluck(:meta_object_id, :adset_id).to_h
      from_spend.merge(cached)
    end
  end

  def destinations
    @destinations ||= Crm::MetaAdObject.where(account_id: @account_id, meta_object_id: adsets.values.uniq)
                                       .where.not(destination_type: nil).pluck(:meta_object_id, :destination_type).to_h
  end
end
