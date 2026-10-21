# O painel do dia a dia de Anúncios da Meta (#1088, F3a): quanto foi investido no período, quantas conversas
# vieram de anúncio, quantas viraram proposta e venda, cada anúncio com o seu veredito e o quanto confiar nos
# números. A ação do dia saiu daqui na F5 (#1110): é o consultor (Crm::MetaAds::Advisor), que não depende do
# período da tela (D5.2). O "quanto confiar" segue o período (D5.8).
#
# O período (Panel::Period, #2011) é um dos nomes da tela — últimos 7, 30 ou 90 dias, este mês, mês passado ou desde
# o primeiro anúncio —, em dias do fuso da conta de anúncios (o mesmo em que a Meta conta o gasto). Tudo sai do
# banco: gasto da coleta diária (F2a), ligações conversa → anúncio (F2b) e cards do CRM.
#
# Sem conexão (`connection` nil, Anúncios sem login, #1960): só o que o WhatsApp contou. Sem gasto, o fuso é o da
# conta, o nome do anúncio é o título que veio no clique e a foto é a guardada do clique (MetaAdObject#image). Custo
# e veredito ficam nil: sem gasto não há o que dividir, e "R$ 0 por venda" leria como anúncio de graça.
# Cada anúncio e o total também dizem quantos estão em negociação (card aberto) e quantos se perderam.
#
# Com conexão (#2054), os anúncios se separam em dois blocos. `ads` são os que levam para o WhatsApp: os que trouxeram
# conversa (nosso clique ou a contagem da Meta, em qualquer época); o gasto, o custo por conversa e o custo por venda
# saem só deles. `other_ads` são os demais (site, alcance, vídeo…): gasto e o resultado que a Meta mede (cliques e
# impressões), sem conversa nem venda, para o gasto deles não inflar o custo de quem leva ao WhatsApp.
#
# O anúncio por dentro (F3b, Panel::AdDetail) lê daqui o período, a coorte, a linha do anúncio e a média da conta,
# para que o número da lista e o da tela do anúncio nunca divirjam.
class Crm::MetaAds::Panel::Report
  attr_reader :zone, :account_id, :period

  # period: nome do Panel::Period; days: o pedido antigo (7 ou 30), para quem ainda chama assim.
  def initialize(connection, period: nil, days: nil, account: nil)
    @connection = connection
    @account_id = connection&.account_id || account.id
    @zone = zone_for(connection, account)
    @period = Crm::MetaAds::Panel::Period.new(Crm::MetaAds::Panel::Period.key_for(period: period, days: days),
                                              today: today, first_ad_day: -> { first_ad_day })
  end

  def payload
    base = { period: period.key, days: days, from: first_day, to: last_day, open: period.open?, currency: currency,
             totals: totals.merge(other_spend: other_ads.sum { |row| row[:spend] }.round(2)), ads: ads, other_ads: other_ads }
    return base.merge(confidence: confidence) unless whatsapp_only?

    base.merge(source: 'whatsapp', totals: totals.merge(spend: nil, other_spend: nil), ads: ads.map { |ad| ad.merge(spend: nil) })
  end

  # Sem conexão: o painel só com o que o WhatsApp contou (#1960).
  def whatsapp_only?
    @connection.nil?
  end

  def today
    @today ||= Time.current.in_time_zone(@zone).to_date
  end

  def days
    period.days
  end

  def first_day
    period.first_day
  end

  def last_day
    period.last_day
  end

  # Do início do primeiro dia ao fim do último, no fuso da conta de anúncios, sem passar de agora. A coorte, o tempo
  # de resposta e o "quanto confiar" do período usam este mesmo intervalo.
  def range
    @range ||= first_day.in_time_zone(@zone)..[last_day.in_time_zone(@zone).end_of_day, Time.current].min
  end

  def cohort
    @cohort ||= (whatsapp_only? ? Crm::MetaAds::Panel::WhatsappCohort : Crm::MetaAds::Panel::Cohort).new(@account_id, range)
  end

  def insights
    return Crm::MetaAdInsightDaily.none if whatsapp_only?

    Crm::MetaAdInsightDaily.where(account_id: @account_id, ad_account_id: @connection.ad_account_id, date: first_day..last_day)
  end

  def currency
    insights.where.not(currency: nil).pick(:currency) || 'BRL'
  end

  def ads
    @ads ||= whatsapp_ad_ids.map { |ad_id| ad_row(ad_id) }
                            .map { |row| row.merge(verdict: whatsapp_only? ? nil : verdict(row)) }
                            .sort_by { |row| [-row[:sales], -row[:conversations], -row[:spend]] }
  end

  # Anúncios com gasto que não levam para o WhatsApp, do maior gasto ao menor.
  def other_ads
    @other_ads ||= (spend_by_ad.keys - whatsapp_ad_ids).map { |ad_id| other_ad_row(ad_id) }.sort_by { |row| -row[:spend] }
  end

  # Custo por venda da conta, só com os anúncios que venderam; nil enquanto nenhum vendeu.
  def average_cost_per_sale
    return @average_cost_per_sale if defined?(@average_cost_per_sale)

    selling = whatsapp_ad_ids.map { |ad_id| ad_row(ad_id) }.select { |row| row[:sales].positive? }
    @average_cost_per_sale = ratio(selling.sum { |row| row[:spend] }, selling.sum { |row| row[:sales] })
  end

  private

  # Dia do primeiro toque de anúncio da conta (e, com conexão, do primeiro gasto guardado), para "desde o primeiro
  # anúncio". Lido só quando esse é o período pedido.
  def first_ad_day
    all_time = Time.zone.at(0)..Time.current
    cohort_class = whatsapp_only? ? Crm::MetaAds::Panel::WhatsappCohort : Crm::MetaAds::Panel::Cohort
    days = [cohort_class.new(@account_id, all_time).first_touch_at&.in_time_zone(@zone)&.to_date]
    days << insights_since_ever.minimum(:date) unless whatsapp_only?
    days.compact.min
  end

  def insights_since_ever
    Crm::MetaAdInsightDaily.where(account_id: @account_id, ad_account_id: @connection.ad_account_id)
  end

  def zone_for(connection, account)
    name = connection ? connection.ad_account_timezone : account.reporting_timezone
    (name.present? && ActiveSupport::TimeZone[name]) || Time.zone
  end

  def spend_by_ad
    @spend_by_ad ||= insights.group(:ad_id).sum(:spend).transform_values(&:to_f)
  end

  def totals
    @totals ||= {
      spend: total_spend.round(2), conversations: cohort.conversation_ads.size, quotes: cohort.cards.count(&:quote?),
      open_quotes: cohort.cards.count { |card| card.quote? && !card.sale? },
      cost_per_conversation: ratio(total_spend, cohort.conversation_ads.size)
    }.merge(sales_totals, outcome_counts(cohort.cards))
  end

  # Em negociação (card aberto, com o valor) e perdidos: o "o que virou" da frase do painel sem login (#1960).
  def outcome_counts(cards)
    open = cards.select(&:open?)
    { open: open.size, open_value: open.sum(&:value).round(2), lost: cards.count(&:lost?) }
  end

  def sales_totals
    sales = cohort.cards.select(&:sale?)
    value = sales.sum(&:value)
    # Sem venda não há retorno a mostrar: "voltou R$ 0" lê como prejuízo antes da hora.
    { sales: sales.size, sales_value: value.round(2), cost_per_sale: ratio(total_spend, sales.size),
      return_per_real: sales.any? ? ratio(value, total_spend) : nil }
  end

  # Gasto dos anúncios que levam para o WhatsApp: é dele que saem o custo por conversa e por venda.
  def total_spend
    whatsapp_ad_ids.sum { |ad_id| spend_by_ad.fetch(ad_id, 0.0) }
  end

  def whatsapp_ad_ids
    @whatsapp_ad_ids ||= (spend_by_ad.keys.select { |ad_id| messaging_ad_ids.include?(ad_id) } +
                          cohort.conversation_ads.values.compact).uniq
  end

  # Anúncio de conversa: já trouxe conversa pelo clique (qualquer época) ou a Meta já contou conversa iniciada nele.
  def messaging_ad_ids
    @messaging_ad_ids ||= if whatsapp_only?
                            Set.new
                          else
                            Set.new(insights_since_ever.where(conversations_started: 1..).distinct.pluck(:ad_id)) |
                              Crm::MetaAdLink.where(account_id: @account_id, ad_id: spend_by_ad.keys).distinct.pluck(:ad_id)
                          end
  end

  def other_metrics
    @other_metrics ||= insights.group(:ad_id).pluck(:ad_id, Arel.sql('SUM(impressions)'), Arel.sql('SUM(link_clicks)'))
                               .to_h { |ad_id, impressions, clicks| [ad_id, { impressions: impressions.to_i, link_clicks: clicks.to_i }] }
  end

  def other_ad_row(ad_id)
    { ad_id: ad_id, spend: spend_by_ad.fetch(ad_id, 0.0).round(2) }
      .merge(other_metrics.fetch(ad_id, { impressions: 0, link_clicks: 0 }), ad_look(ad_id))
  end

  def ad_row(ad_id)
    @ad_rows ||= {}
    @ad_rows[ad_id] ||= build_ad_row(ad_id)
  end

  def build_ad_row(ad_id)
    cards = cohort.cards.select { |card| card.ad_id == ad_id }
    sales = cards.select(&:sale?)
    spend = spend_by_ad.fetch(ad_id, 0.0)
    {
      ad_id: ad_id, spend: spend.round(2), conversations: cohort.conversation_ads.values.count(ad_id),
      quotes: cards.count(&:quote?), sales: sales.size, sales_value: sales.sum(&:value).round(2), cost_per_sale: ratio(spend, sales.size)
    }.merge(ad_look(ad_id), outcome_counts(cards))
  end

  # Nome (o resolvido pela Meta, senão o título do clique) e imagens do anúncio.
  def ad_look(ad_id)
    object = objects[ad_id]
    name = object&.name.presence || (headlines[ad_id] if whatsapp_only?)
    { name: name, thumbnail_url: object&.thumbnail_url, image_url: object&.image_path }
  end

  def objects
    @objects ||= Crm::MetaAdObject.where(account_id: @account_id, meta_object_id: whatsapp_ad_ids + spend_by_ad.keys)
                                  .with_attached_image.index_by(&:meta_object_id)
  end

  # Título que veio no clique (o `headline` do toque), para o anúncio que ainda não tem nome resolvido pela Meta.
  def headlines
    @headlines ||= Conversation.where(account_id: @account_id, id: cohort.conversation_ads.keys)
                               .pluck(:additional_attributes)
                               .flat_map { |attrs| [attrs.to_h['campaign'], *Array(attrs.to_h['campaign_touches'])] }
                               .each_with_object({}) { |touch, all| headline_for(touch, all) }
  end

  def headline_for(touch, all)
    return unless touch.is_a?(Hash) && touch['source_id'].present? && touch['headline'].present?

    all[touch['source_id'].to_s] ||= touch['headline'].to_s.first(Crm::MetaAdObject::NAME_LIMIT)
  end

  def verdict(row)
    Crm::MetaAds::Panel::Verdict.for(conversations: row[:conversations], sales: row[:sales], cost_per_sale: row[:cost_per_sale],
                                     average_cost_per_sale: average_cost_per_sale)
  end

  def confidence
    @confidence ||= Crm::MetaAds::Links::Stats.new(@connection, since: range.begin).payload[:confidence]
  end

  def ratio(numerator, denominator)
    return if whatsapp_only? || denominator.to_f.zero?

    (numerator.to_f / denominator).round(2)
  end
end
