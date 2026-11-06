# Os anúncios que levam para fora de conversa (#2054, #2521), para o Panel::Report separar "Outros anúncios" dos que
# trazem conversa, e a regra única de quais ligações conversa → anúncio contam (`counted_links`).
#
# Fora dos que trazem conversa: nunca trouxe conversa pelo clique e a Meta diz que o conjunto leva a outro lugar (site,
# vídeo, perfil, alcance…, Panel::AdDestinations). A conversa que só a Meta contou pesa apenas quando o destino não está
# dito (#2621). Anúncio novo de WhatsApp, ainda sem a primeira mensagem, continua entre
# os que trazem conversa. A classificação é do anúncio, não do período: o destino e o objetivo vêm do conjunto
# (Crm::MetaAdObject), com ou sem gasto no período.
#
# A conversa do privado de um comentário (#2521, origem `comment`) não muda o lugar do anúncio: o de alcance ou perfil
# continua em "Outros anúncios", e essas conversas são o resultado dele ali (`private_conversations`). Elas ficam fora
# de toda conta de conversa da coorte — painel, caixa de confiança, tempo de resposta, resumo diário, alerta de gasto,
# consultor —, que lê as ligações por `counted_links`. Decisão da Meta aprovar, seguindo o protótipo aprovado.
class Crm::MetaAds::Panel::OutsideAds
  COMMENT = Crm::MetaAds::Links::CommentTouch::ORIGIN

  # As ligações de `links` que contam como conversa de anúncio: todas, menos as de comentário de anúncio de fora.
  def self.counted_links(account_id, links)
    outside = new(account_id, ad_ids: links.where(origin: COMMENT).distinct.pluck(:ad_id)).ids
    return links if outside.empty?

    links.where.not(origin: COMMENT).or(links.where.not(ad_id: outside))
  end

  # ad_ids: os anúncios a classificar; range: o período das `private_conversations`.
  def initialize(account_id, ad_ids:, range: nil)
    @account_id = account_id
    @ad_ids = ad_ids.compact.uniq
    @range = range
  end

  def include?(ad_id)
    return false unless destinations.outside_conversation?(ad_id)
    return false if linked_ad_ids.include?(ad_id)

    destinations.stated_outside?(ad_id) || meta_counted_ad_ids.exclude?(ad_id)
  end

  def ids
    @ids ||= @ad_ids.select { |ad_id| include?(ad_id) }
  end

  # Para onde leva e as conversas do privado de um comentário no período.
  def row(ad_id)
    { destination: destinations.kind(ad_id), private_conversations: private_conversations.fetch(ad_id, 0) }
  end

  private

  def insights
    Crm::MetaAdInsightDaily.where(account_id: @account_id, ad_id: @ad_ids)
  end

  # O conjunto de cada anúncio sai do cache de nomes ou do gasto de qualquer época (AdDestinations).
  def destinations
    @destinations ||= Crm::MetaAds::Panel::AdDestinations.new(@account_id, insights)
  end

  def private_conversations
    @private_conversations ||= Crm::MetaAdLink.where(account_id: @account_id, ad_id: ids, touched_at: @range, origin: COMMENT)
                                              .group(:ad_id).distinct.count(:conversation_id)
  end

  # Já trouxe conversa pelo clique, em qualquer época (o site com botão do WhatsApp, por exemplo): fica entre os que
  # trazem conversa, qualquer que seja o destino.
  def linked_ad_ids
    @linked_ad_ids ||= Set.new(Crm::MetaAdLink.where(account_id: @account_id, ad_id: @ad_ids).where.not(origin: COMMENT)
                                              .distinct.pluck(:ad_id))
  end

  # A Meta contou conversa iniciada nele. Só decide quando o destino não está dito (UNDEFINED, decidido pelo objetivo):
  # no de perfil, a conversa que a Meta conta é de quem chamou pelo perfil, e ele continua de perfil (#2621, "Filha").
  def meta_counted_ad_ids
    @meta_counted_ad_ids ||= Set.new(insights.where(conversations_started: 1..).distinct.pluck(:ad_id))
  end
end
