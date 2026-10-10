# O painel do dia a dia de Anúncios da Meta (#1088, F3a): quanto foi investido no período, quantas conversas
# vieram de anúncio, quantas viraram proposta e venda, cada anúncio com o seu veredito e o quanto confiar nos
# números. A ação do dia saiu daqui na F5 (#1110): é o consultor (Crm::MetaAds::Advisor), que não depende do
# período da tela (D5.2). O "quanto confiar" segue o período (D5.8).
#
# O período são os últimos `days` dias contando hoje, no fuso da conta de anúncios (o mesmo em que a Meta conta
# o gasto). Tudo sai do banco: gasto da coleta diária (F2a), ligações conversa → anúncio (F2b) e cards do CRM.
#
# O anúncio por dentro (F3b, Panel::AdDetail) lê daqui o período, a coorte, a linha do anúncio e a média da conta,
# para que o número da lista e o da tela do anúncio nunca divirjam.
class Crm::MetaAds::Panel::Report
  PERIODS = [7, 30].freeze

  attr_reader :days, :zone

  def initialize(connection, days:)
    @connection = connection
    @days = PERIODS.include?(days.to_i) ? days.to_i : PERIODS.last
    @zone = (connection.ad_account_timezone.present? && ActiveSupport::TimeZone[connection.ad_account_timezone]) || Time.zone
  end

  def payload
    {
      days: @days, from: first_day, to: today, currency: currency, totals: totals, ads: ads, confidence: confidence
    }
  end

  def today
    @today ||= Time.current.in_time_zone(@zone).to_date
  end

  def first_day
    today - (@days - 1)
  end

  # Do início do primeiro dia, no fuso da conta de anúncios, até agora. A coorte, o tempo de resposta e o "quanto
  # confiar" do período usam este mesmo intervalo.
  def range
    @range ||= first_day.in_time_zone(@zone)..Time.current
  end

  def cohort
    @cohort ||= Crm::MetaAds::Panel::Cohort.new(@connection.account_id, range)
  end

  def insights
    Crm::MetaAdInsightDaily.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id, date: first_day..today)
  end

  def currency
    insights.where.not(currency: nil).pick(:currency) || 'BRL'
  end

  def ads
    @ads ||= ad_ids.map { |ad_id| ad_row(ad_id) }
                   .map { |row| row.merge(verdict: verdict(row)) }
                   .sort_by { |row| [-row[:sales], -row[:conversations], -row[:spend]] }
  end

  # Custo por venda da conta, só com os anúncios que venderam; nil enquanto nenhum vendeu.
  def average_cost_per_sale
    return @average_cost_per_sale if defined?(@average_cost_per_sale)

    selling = ad_ids.map { |ad_id| ad_row(ad_id) }.select { |row| row[:sales].positive? }
    @average_cost_per_sale = ratio(selling.sum { |row| row[:spend] }, selling.sum { |row| row[:sales] })
  end

  private

  def spend_by_ad
    @spend_by_ad ||= insights.group(:ad_id).sum(:spend).transform_values(&:to_f)
  end

  def totals
    @totals ||= {
      spend: total_spend.round(2), conversations: cohort.conversation_ads.size, quotes: cohort.cards.count(&:quote?),
      open_quotes: cohort.cards.count { |card| card.quote? && !card.sale? },
      cost_per_conversation: ratio(total_spend, cohort.conversation_ads.size)
    }.merge(sales_totals)
  end

  def sales_totals
    sales = cohort.cards.select(&:sale?)
    value = sales.sum(&:value)
    # Sem venda não há retorno a mostrar: "voltou R$ 0" lê como prejuízo antes da hora.
    { sales: sales.size, sales_value: value.round(2), cost_per_sale: ratio(total_spend, sales.size),
      return_per_real: sales.any? ? ratio(value, total_spend) : nil }
  end

  def total_spend
    spend_by_ad.values.sum
  end

  def ad_ids
    (spend_by_ad.keys + cohort.conversation_ads.values.compact).uniq
  end

  def ad_row(ad_id)
    @ad_rows ||= {}
    @ad_rows[ad_id] ||= build_ad_row(ad_id)
  end

  def build_ad_row(ad_id)
    cards = cohort.cards.select { |card| card.ad_id == ad_id }
    sales = cards.select(&:sale?)
    spend = spend_by_ad.fetch(ad_id, 0.0)
    object = objects[ad_id]
    {
      ad_id: ad_id, name: object&.name, thumbnail_url: object&.thumbnail_url, spend: spend.round(2),
      conversations: cohort.conversation_ads.values.count(ad_id), quotes: cards.count(&:quote?), sales: sales.size,
      sales_value: sales.sum(&:value).round(2), cost_per_sale: ratio(spend, sales.size)
    }
  end

  def objects
    @objects ||= Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: ad_ids).index_by(&:meta_object_id)
  end

  def verdict(row)
    Crm::MetaAds::Panel::Verdict.for(conversations: row[:conversations], sales: row[:sales], cost_per_sale: row[:cost_per_sale],
                                     average_cost_per_sale: average_cost_per_sale)
  end

  def confidence
    @confidence ||= Crm::MetaAds::Links::Stats.new(@connection, since: range.begin).payload[:confidence]
  end

  def ratio(numerator, denominator)
    return if denominator.to_f.zero?

    (numerator.to_f / denominator).round(2)
  end
end
