# Para onde cada anúncio leva (#2054), pelo `destination_type` do conjunto que a Meta manda (Crm::MetaAds::Insights::Destinations).
#
# Só afirma "não leva a uma conversa" quando a Meta disse um destino que está em OUTSIDE (site, app, vídeo, perfil…).
# O destino UNDEFINED a Meta devolve também em alcance, reconhecimento e engajamento (#2521): aí quem decide é o
# objetivo do conjunto (`optimization_goal`), e só os de OUTSIDE_GOALS saem dos que trazem conversa. Sem o destino nem
# o objetivo — conjunto ainda não lido, ou um valor novo da Meta — não afirma nada: o anúncio segue entre os que trazem
# conversa, como um anúncio novo de WhatsApp sem a primeira mensagem.
#
# `kind` diz o destino em palavras para a tela (perfil, publicação, formulário, site…) e qual número da Meta mede o
# anúncio que não abre conversa (Panel::Report#other_ad_row).
class Crm::MetaAds::Panel::AdDestinations
  # Os destinos que não são de mensagem, da referência do conjunto de anúncios (Marketing API, destination_type,
  # conferida em 21/10/2026). Os de mensagem (WHATSAPP, MESSENGER, INSTAGRAM_DIRECT e os MESSAGING_*) ficam de fora.
  OUTSIDE = %w[
    WEBSITE APP APPLINKS_AUTOMATIC FACEBOOK SHOP_AUTOMATIC ON_AD ON_POST ON_EVENT ON_VIDEO ON_PAGE INSTAGRAM_PROFILE
    FACEBOOK_PAGE INSTAGRAM_PROFILE_AND_FACEBOOK_PAGE INSTAGRAM_LIVE FACEBOOK_LIVE IMAGINE
  ].freeze
  UNDEFINED = 'UNDEFINED'.freeze

  # Objetivos do conjunto que não são de conversa (Marketing API, optimization_goal, conferida em 04/11/2026). Os de
  # conversa (CONVERSATIONS, MESSAGING_*) e os que a Meta ainda inventar ficam de fora: na dúvida, traz conversa.
  OUTSIDE_GOALS = %w[
    REACH IMPRESSIONS AD_RECALL_LIFT POST_ENGAGEMENT PAGE_LIKES THRUPLAY EVENT_RESPONSES LINK_CLICKS LANDING_PAGE_VIEWS
    VISIT_INSTAGRAM_PROFILE PROFILE_VISIT PROFILE_AND_PAGE_ENGAGEMENT LEAD_GENERATION QUALITY_LEAD OFFSITE_CONVERSIONS
    VALUE APP_INSTALLS
  ].freeze

  # O destino em palavras, do mais específico (o destino) ao do objetivo. A tela tem um texto para cada um.
  KIND_BY_DESTINATION = {
    'INSTAGRAM_PROFILE' => 'profile', 'FACEBOOK_PAGE' => 'profile', 'INSTAGRAM_PROFILE_AND_FACEBOOK_PAGE' => 'profile',
    'ON_PAGE' => 'profile', 'ON_POST' => 'post', 'ON_VIDEO' => 'post', 'ON_EVENT' => 'post', 'INSTAGRAM_LIVE' => 'post',
    'FACEBOOK_LIVE' => 'post', 'ON_AD' => 'lead_form', 'WEBSITE' => 'website', 'SHOP_AUTOMATIC' => 'website',
    'APP' => 'app', 'APPLINKS_AUTOMATIC' => 'app'
  }.freeze
  KIND_BY_GOAL = {
    'VISIT_INSTAGRAM_PROFILE' => 'profile', 'PROFILE_VISIT' => 'profile', 'PROFILE_AND_PAGE_ENGAGEMENT' => 'profile',
    'PAGE_LIKES' => 'profile', 'POST_ENGAGEMENT' => 'post', 'THRUPLAY' => 'post', 'EVENT_RESPONSES' => 'post',
    'LEAD_GENERATION' => 'lead_form', 'QUALITY_LEAD' => 'lead_form', 'LINK_CLICKS' => 'website',
    'LANDING_PAGE_VIEWS' => 'website', 'OFFSITE_CONVERSIONS' => 'website', 'VALUE' => 'website', 'APP_INSTALLS' => 'app',
    'REACH' => 'reach', 'IMPRESSIONS' => 'reach', 'AD_RECALL_LIFT' => 'reach'
  }.freeze
  OTHER = 'other'.freeze

  # insights: as linhas de gasto do período (trazem o conjunto de cada anúncio).
  def initialize(account_id, insights)
    @account_id = account_id
    @insights = insights
  end

  def outside_conversation?(ad_id)
    destination, goal = adset_of(ad_id)
    return OUTSIDE.include?(destination) unless destination == UNDEFINED

    OUTSIDE_GOALS.include?(goal)
  end

  # Para onde leva o anúncio que não abre conversa: profile, post, lead_form, website, app, reach ou other.
  def kind(ad_id)
    destination, goal = adset_of(ad_id)
    KIND_BY_DESTINATION[destination] || KIND_BY_GOAL[goal] || OTHER
  end

  private

  # [destino, objetivo] do conjunto do anúncio.
  def adset_of(ad_id)
    adsets_read.fetch(adsets[ad_id], [nil, nil])
  end

  # Conjunto de cada anúncio: o do cache de nomes e, enquanto o anúncio não foi resolvido, o que veio no gasto.
  def adsets
    @adsets ||= begin
      from_spend = @insights.where.not(adset_id: nil).distinct.pluck(:ad_id, :adset_id).to_h
      cached = Crm::MetaAdObject.where(account_id: @account_id, meta_object_id: @insights.distinct.pluck(:ad_id))
                                .where.not(adset_id: nil).pluck(:meta_object_id, :adset_id).to_h
      from_spend.merge(cached)
    end
  end

  def adsets_read
    @adsets_read ||= Crm::MetaAdObject.where(account_id: @account_id, meta_object_id: adsets.values.uniq)
                                      .where.not(destination_type: nil)
                                      .pluck(:meta_object_id, :destination_type, :optimization_goal)
                                      .to_h { |id, destination, goal| [id, [destination, goal]] }
  end
end
