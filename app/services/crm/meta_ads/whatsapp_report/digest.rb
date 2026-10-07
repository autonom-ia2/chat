# Os números do resumo diário (#1100, F4b): o dia de ontem no fuso da conta de anúncios, o mesmo em que a Meta
# conta o gasto.
#
# Gasto de `crm_meta_ad_insights_daily` (date = ontem); conversas, propostas e vendas da mesma coorte do painel
# (`Panel::Cohort`) com o intervalo de ontem; o anúncio que mais trouxe conversa; e o que fazer hoje.
#
# O que fazer hoje (F5, #1110): a primeira ação do consultor (Crm::MetaAds::Advisor::Analysis), a mesma que o
# painel mostra em primeiro, porque o consultor não depende do período da tela (D5.2). Com `with_ai: true` (o
# envio das 8h), `Analysis.daily` escreve o texto pela IA se o run do dia ainda não tem texto e há vaga no teto;
# a ação vem com `source: 'ai'` e o texto pronto, ou com `source: 'rule'` e os fatos, que o MessageBuilder
# formata. O envio de teste não chama a IA (`Analysis.current`, sem escrita). O envio real marca a ação como
# mostrada (`mark_shown!`), o de teste não.
class Crm::MetaAds::WhatsappReport::Digest
  def initialize(connection, with_ai: false)
    @connection = connection
    @with_ai = with_ai
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

  # Ontem sem gasto e sem conversa: não há o que contar. Não monta o `payload`, para não chamar a IA à toa.
  def nothing_to_report?
    spend.zero? && cohort.conversation_ads.empty?
  end

  # Depois do envio real: a ação que o WhatsApp mostrou conta como mostrada na métrica de aceite. Os fillers
  # (`wait`, `on_track`, `no_data`) não têm linha nem id.
  def mark_shown!
    id = payload.dig(:action, :id)
    Crm::MetaAds::Advisor::Analysis.mark_shown!([id]) if id
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

  # A primeira ação do consultor, no idioma em que o resumo sai.
  def action
    analysis = Crm::MetaAds::Advisor::Analysis
    advice = @with_ai ? analysis.daily(@connection, language: language) : analysis.current(@connection, locale: language, trigger: 'digest')
    advice[:actions].first
  end

  def language
    Crm::MetaAds::WhatsappReport::MessageBuilder.new(@connection.account).language
  end

  def ratio(numerator, denominator)
    return if denominator.to_f.zero?

    (numerator.to_f / denominator).round(2)
  end
end
