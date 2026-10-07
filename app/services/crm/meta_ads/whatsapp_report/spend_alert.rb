# O anúncio que gastou hoje sem trazer conversa (#1100, F4b), no fuso da conta de anúncios.
#
# Entra o anúncio com gasto de hoje maior ou igual a ALERT_SPEND_FACTOR vezes o custo por conversa da conta nos
# últimos 30 dias e nenhuma conversa hoje. Sem custo por conversa (nenhuma conversa nos 30 dias), o piso é
# ALERT_MIN_SPEND na moeda da conta. Havendo mais de um, vai o de maior gasto: uma mensagem só.
class Crm::MetaAds::WhatsappReport::SpendAlert
  ALERT_SPEND_FACTOR = 2
  ALERT_MIN_SPEND = 30
  BASELINE_DAYS = 30

  def initialize(connection)
    @connection = connection
    @zone = (connection.ad_account_timezone.present? && ActiveSupport::TimeZone[connection.ad_account_timezone]) || Time.zone
  end

  # { ad_id:, name:, spend:, currency:, threshold: } ou nil.
  def candidate
    return @candidate if defined?(@candidate)

    ad_id, spent = spend_by_ad.select { |id, value| value >= threshold && conversations_today[id].to_i.zero? }
                              .max_by { |_id, value| value }
    @candidate = ad_id && { ad_id: ad_id, name: ad_name(ad_id), spend: spent.round(2), currency: currency, threshold: threshold }
  end

  def threshold
    @threshold ||= begin
      cost = Crm::MetaAds::Panel::Report.new(@connection, days: BASELINE_DAYS).payload.dig(:totals, :cost_per_conversation)
      cost ? (cost * ALERT_SPEND_FACTOR).round(2) : ALERT_MIN_SPEND
    end
  end

  private

  def today
    Time.current.in_time_zone(@zone).to_date
  end

  def insights
    Crm::MetaAdInsightDaily.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id, date: today)
  end

  def spend_by_ad
    insights.group(:ad_id).sum(:spend).transform_values(&:to_f)
  end

  # { ad_id => conversas de hoje }
  def conversations_today
    @conversations_today ||= Crm::MetaAds::Panel::Cohort.new(@connection.account_id, today.in_time_zone(@zone).beginning_of_day..Time.current)
                                                        .conversation_ads.values.compact.tally
  end

  def currency
    insights.where.not(currency: nil).pick(:currency) || 'BRL'
  end

  def ad_name(ad_id)
    Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: ad_id).pick(:name).presence || ad_id
  end
end
