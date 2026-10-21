# Para onde cada anúncio leva (#2054), pelo `destination_type` do conjunto que a Meta manda (Crm::MetaAds::NameResolver).
#
# Só afirma "não leva a uma conversa" quando a Meta disse o destino e ele não é de mensagem (site, vídeo, perfil…).
# Sem o destino — conjunto ainda não resolvido, ou a Meta não mandou — não afirma nada: o anúncio segue entre os que
# trazem conversa, como um anúncio novo de WhatsApp que ainda não recebeu a primeira mensagem.
class Crm::MetaAds::Panel::AdDestinations
  # Os destinos de mensagem da referência do conjunto de anúncios (Marketing API, campo destination_type).
  MESSAGING = %w[
    WHATSAPP MESSENGER INSTAGRAM_DIRECT MESSAGING_MESSENGER_WHATSAPP MESSAGING_INSTAGRAM_DIRECT_MESSENGER
    MESSAGING_INSTAGRAM_DIRECT_MESSENGER_WHATSAPP MESSAGING_INSTAGRAM_DIRECT_WHATSAPP
  ].freeze
  UNDEFINED = 'UNDEFINED'.freeze

  # insights: as linhas de gasto do período (trazem o conjunto de cada anúncio).
  def initialize(account_id, insights)
    @account_id = account_id
    @insights = insights
  end

  def outside_conversation?(ad_id)
    destination = destinations[adsets[ad_id]]
    destination.present? && destination != UNDEFINED && MESSAGING.exclude?(destination)
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
