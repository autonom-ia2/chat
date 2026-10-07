# Os números do resumo diário (#1100, F4b): o dia de ontem no fuso da conta de anúncios, o mesmo em que a Meta
# conta o gasto.
#
# Gasto de `crm_meta_ad_insights_daily` (date = ontem); conversas, propostas e vendas da mesma coorte do painel
# (`Panel::Cohort`) com o intervalo de ontem; o anúncio que mais trouxe conversa; e o que fazer hoje — a ação da
# regra (`Panel::Action`) dos últimos 7 dias.
#
# O resumo usa sempre a regra, nunca o texto da IA (F4a): o texto da IA só existe depois que alguém abre o painel no
# dia, no período e no idioma de quem abriu; às 8h quase nunca haveria um, e o resumo não chama a IA sozinho.
class Crm::MetaAds::WhatsappReport::Digest
  ACTION_DAYS = 7

  def initialize(connection)
    @connection = connection
    @zone = (connection.ad_account_timezone.present? && ActiveSupport::TimeZone[connection.ad_account_timezone]) || Time.zone
  end

  def date
    @date ||= Time.current.in_time_zone(@zone).to_date - 1
  end

  def payload
    @payload ||= {
      date: date, currency: currency, spend: spend, conversations: cohort.conversation_ads.size,
      cost_per_conversation: ratio(spend, cohort.conversation_ads.size), quotes: cohort.cards.count(&:quote?),
      sales: sales.size, sales_value: sales.sum(&:value).round(2), best_ad: best_ad, action: action
    }
  end

  # Ontem sem gasto e sem conversa: não há o que contar.
  def nothing_to_report?
    payload[:spend].zero? && payload[:conversations].zero?
  end

  private

  def insights
    Crm::MetaAdInsightDaily.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id, date: date)
  end

  def spend
    @spend ||= insights.sum(:spend).to_f.round(2)
  end

  def currency
    insights.where.not(currency: nil).pick(:currency) || 'BRL'
  end

  def cohort
    @cohort ||= Crm::MetaAds::Panel::Cohort.new(@connection.account_id, date.in_time_zone(@zone).all_day)
  end

  def sales
    @sales ||= cohort.cards.select(&:sale?)
  end

  def best_ad
    ad_id, count = cohort.conversation_ads.values.compact.tally.max_by { |_id, total| total }
    return if ad_id.nil?

    name = Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: ad_id).pick(:name)
    { ad_id: ad_id, name: name.presence || ad_id, conversations: count }
  end

  def action
    Crm::MetaAds::Panel::Report.new(@connection, days: ACTION_DAYS).payload[:action]
  end

  def ratio(numerator, denominator)
    return if denominator.to_f.zero?

    (numerator.to_f / denominator).round(2)
  end
end
