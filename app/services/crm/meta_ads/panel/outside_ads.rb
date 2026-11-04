# Os anúncios com gasto que levam para fora de conversa (#2054, #2521), para o Panel::Report separar "Outros anúncios"
# dos que trazem conversa.
#
# Fora dos que trazem conversa: nunca trouxe conversa e a Meta diz que o conjunto leva a outro lugar (site, vídeo,
# perfil, alcance…, Panel::AdDestinations). Anúncio novo de WhatsApp, ainda sem a primeira mensagem, continua entre
# os que trazem conversa.
#
# A conversa do privado de um comentário (#2521, origem `comment`) não muda o lugar do anúncio: o de alcance ou perfil
# continua em "Outros anúncios", e essas conversas são o resultado dele ali (`private_conversations`), fora da coorte
# e do custo por conversa (Panel::Cohort `outside_comment_ads`). Decisão da Meta aprovar, seguindo o protótipo aprovado.
class Crm::MetaAds::Panel::OutsideAds
  COMMENT = Crm::MetaAds::Links::CommentTouch::ORIGIN

  # insights: as linhas de gasto do período; ever: todas as da conta de anúncios; spend_by_ad: { ad_id => gasto }.
  def initialize(account_id, insights:, ever:, spend_by_ad:, range:)
    @account_id = account_id
    @insights = insights
    @ever = ever
    @spend_by_ad = spend_by_ad
    @range = range
  end

  def include?(ad_id)
    messaging_ad_ids.exclude?(ad_id) && destinations.outside_conversation?(ad_id)
  end

  def ids
    @ids ||= @spend_by_ad.keys.select { |ad_id| include?(ad_id) }
  end

  # Para onde leva e as conversas do privado de um comentário no período.
  def row(ad_id)
    { destination: destinations.kind(ad_id), private_conversations: private_conversations.fetch(ad_id, 0) }
  end

  private

  def destinations
    @destinations ||= Crm::MetaAds::Panel::AdDestinations.new(@account_id, @insights)
  end

  def private_conversations
    @private_conversations ||= Crm::MetaAdLink.where(account_id: @account_id, ad_id: ids, touched_at: @range, origin: COMMENT)
                                              .group(:ad_id).distinct.count(:conversation_id)
  end

  # Já trouxe conversa: pelo clique (qualquer época) ou a Meta já contou conversa iniciada nele.
  def messaging_ad_ids
    @messaging_ad_ids ||= Set.new(@ever.where(ad_id: @spend_by_ad.keys, conversations_started: 1..).distinct.pluck(:ad_id)) |
                          Crm::MetaAdLink.where(account_id: @account_id, ad_id: @spend_by_ad.keys).where.not(origin: COMMENT)
                                         .distinct.pluck(:ad_id)
  end
end
