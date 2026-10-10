# Os fatos do consultor de anúncios (#1110, F5, §1.2): tudo o que as regras olham, calculado pelo código. Só
# números, ids, datas e nome de anúncio — nunca título de card, contato ou texto de conversa —, porque os fatos vão
# para o run e, por ação, para a IA.
#
# O consultor não depende do período da tela (D5.2): a coorte é sempre a de 30 dias (`Panel::Report`), e os sinais
# da Meta comparam os últimos 7 dias fechados (até ontem) com as 3 semanas anteriores, no fuso da conta de anúncios.
# As semanas de custo por venda da escala são as duas **maduras** (ontem − 20 … ontem − 7): a mais recente fica
# fora porque as vendas dela ainda estão chegando.
#
# O payload é JSON puro (datas em ISO 8601) e fica 5 min no Redis: o painel pede a cada 2 min por aba. O histórico
# de aceites fica fora (History), senão o cache ficaria velho depois de um aceite. Num cache vazio com o painel em
# 30 dias, o `Report` da própria requisição é reaproveitado.
class Crm::MetaAds::Advisor::Facts
  CACHE_TTL = 5.minutes
  COHORT_DAYS = 30
  RECENT_DAYS = 7
  BASELINE_DAYS = 21
  WEEK_DAYS = 7
  WEEKS = %i[week_a week_b].freeze
  INSIGHT_COLUMNS = %i[ad_id adset_id date spend impressions link_clicks conversations_started].freeze

  def self.cache_key(connection, local_date)
    "crm:meta_ads:advisor:facts:#{Crm::MetaAds::Advisor::Rules::RULES_VERSION}:#{connection.account_id}:" \
      "#{connection.ad_account_id}:#{local_date.iso8601}"
  end

  def initialize(connection, now: Time.current, report: nil)
    @connection = connection
    @now = now
    @report = report if report&.days == COHORT_DAYS
  end

  # Símbolos nas chaves e valores de JSON, iguais com ou sem cache.
  def payload
    @payload ||= JSON.parse(cached || store(build.to_json)).deep_symbolize_keys
  end

  private

  def report
    @report ||= Crm::MetaAds::Panel::Report.new(@connection, days: COHORT_DAYS)
  end

  def local_date
    report.today
  end

  def yesterday
    local_date - 1
  end

  def key
    self.class.cache_key(@connection, local_date)
  end

  def cached
    Redis::Alfred.get(key).presence
  end

  def store(json)
    Redis::Alfred.set(key, json, ex: CACHE_TTL.to_i)
    json
  end

  def build
    { local_date: local_date.iso8601, currency: report.currency, account: account_facts, ads: report.ads.map { |row| ad_facts(row) } }
  end

  def windows
    @windows ||= {
      recent: (yesterday - (RECENT_DAYS - 1))..yesterday,
      baseline: (yesterday - (RECENT_DAYS + BASELINE_DAYS - 1))..(yesterday - RECENT_DAYS),
      week_a: (yesterday - (RECENT_DAYS + WEEK_DAYS - 1))..(yesterday - RECENT_DAYS),
      week_b: (yesterday - (RECENT_DAYS + (2 * WEEK_DAYS) - 1))..(yesterday - RECENT_DAYS - WEEK_DAYS)
    }
  end

  def account_facts
    cohort_facts.merge(signals(insight_rows)).merge(confidence: confidence, stalled: stalled, response: response)
  end

  def cohort_facts
    conversations = report.cohort.conversation_ads.size
    {
      spend_30d: spend_30d, conversations_30d: conversations, cost_per_conversation_30d: ratio(spend_30d, conversations),
      target_cost_per_sale: report.average_cost_per_sale, selling_ads: report.ads.count { |row| row[:sales].positive? }
    }.merge(card_facts(report.cohort.cards))
  end

  def card_facts(cards)
    { quotes_30d: cards.count(&:quote?), open_quotes: cards.count { |card| card.quote? && !card.sale? }, sales_30d: cards.count(&:sale?) }
  end

  def spend_30d
    @spend_30d ||= report.ads.sum { |row| row[:spend] }.round(2)
  end

  # Impressões, cliques e gasto nas duas janelas, com CTR e CPM (nil sem impressão).
  def signals(rows)
    recent = sums(rows, windows[:recent])
    baseline = sums(rows, windows[:baseline])
    {
      impressions_recent: recent[:impressions], impressions_baseline: baseline[:impressions],
      link_clicks_recent: recent[:link_clicks], link_clicks_baseline: baseline[:link_clicks],
      spend_recent: recent[:spend], spend_baseline: baseline[:spend],
      ctr_recent: ctr(recent), ctr_baseline: ctr(baseline), cpm_recent: cpm(recent), cpm_baseline: cpm(baseline)
    }
  end

  def ad_facts(row)
    rows = insight_rows.select { |insight| insight[:ad_id] == row[:ad_id] }
    {
      ad_id: row[:ad_id], ad_name: row[:name], verdict: row[:verdict],
      verdict_reason: Crm::MetaAds::Panel::Verdict.reason(row, average_cost_per_sale: report.average_cost_per_sale),
      spend_30d: row[:spend], conversations: row[:conversations], quotes: row[:quotes], sales: row[:sales], cost_per_sale: row[:cost_per_sale],
      week_a: week(row[:ad_id], rows, :week_a), week_b: week(row[:ad_id], rows, :week_b)
    }.merge(ad_signals(rows), adset_facts(row[:ad_id], rows), frequency_facts(row[:ad_id]))
  end

  def ad_signals(rows)
    signals(rows).slice(:spend_recent, :impressions_recent, :impressions_baseline, :link_clicks_recent, :link_clicks_baseline,
                        :ctr_recent, :ctr_baseline)
  end

  # O conjunto do anúncio (o da coleta mais recente, senão o do cache de nomes) e o que ele fez nos últimos 7 dias.
  def adset_facts(ad_id, rows)
    adset_id = rows.filter_map { |insight| insight[:adset_id] }.last || adsets[ad_id]
    recent = sums(adset_id ? insight_rows.select { |insight| insight[:adset_id] == adset_id } : [], windows[:recent])
    { adset_id: adset_id, adset_meta_results_7d: recent[:conversations_started], adset_spend_recent: recent[:spend] }
  end

  def frequency_facts(ad_id)
    frequency, date_end = frequencies[ad_id]
    { frequency_7d: frequency, frequency_date_end: date_end }
  end

  def week(ad_id, rows, name)
    spend = sums(rows, windows[name])[:spend]
    sales = week_sales.fetch([ad_id, name], 0)
    { spend: spend, sales: sales, cost_per_sale: ratio(spend, sales) }
  end

  # Uma coorte só sobre as duas semanas: cada conversa entra uma vez, na semana do toque que decide o anúncio
  # dela, e a venda conta para essa semana. Nada é contado nas duas.
  def week_sales
    @week_sales ||= week_cohort.cards.select { |card| card.sale? && card.ad_id }.each_with_object(Hash.new(0)) do |card, all|
      day = week_cohort.touches[card.conversation_id].last.in_time_zone(report.zone).to_date
      name = WEEKS.find { |week| windows[week].cover?(day) }
      all[[card.ad_id, name]] += 1 if name
    end
  end

  def week_cohort
    @week_cohort ||= Crm::MetaAds::Panel::Cohort.new(
      @connection.account_id, windows[:week_b].first.in_time_zone(report.zone)...(windows[:week_a].last + 1).in_time_zone(report.zone)
    )
  end

  # As linhas diárias da conta de anúncios, da linha de base até ontem (uma consulta).
  def insight_rows
    @insight_rows ||= Crm::MetaAdInsightDaily
                      .where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id,
                             date: windows[:baseline].first..yesterday)
                      .order(:date).pluck(*INSIGHT_COLUMNS)
                      .map { |values| INSIGHT_COLUMNS.zip(values).to_h }
  end

  def sums(rows, window)
    inside = rows.select { |row| window.cover?(row[:date]) }
    { spend: inside.sum(0.to_d) { |row| row[:spend] }.to_f.round(2), impressions: inside.sum { |row| row[:impressions] },
      link_clicks: inside.sum { |row| row[:link_clicks] }, conversations_started: inside.sum { |row| row[:conversations_started] } }
  end

  def adsets
    @adsets ||= Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: report.ads.pluck(:ad_id))
                                 .pluck(:meta_object_id, :adset_id).to_h
  end

  # A frequência de 7 dias mais recente de cada anúncio, se a Meta a fechou até anteontem (§1.1 `freq7`).
  def frequencies
    @frequencies ||= Crm::MetaAdFrequencyWindow
                     .where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id, window_days: RECENT_DAYS,
                            date_end: (yesterday - 1)..)
                     .order(:date_end)
                     .pluck(:ad_id, :frequency, :date_end)
                     .to_h { |ad_id, frequency, date_end| [ad_id, [frequency&.to_f, date_end.iso8601]] }
  end

  def confidence
    Crm::MetaAds::Links::Stats.new(@connection, since: cohort_start).payload[:confidence].slice(:conversations, :ad, :ad_name, :unknown)
  end

  def cohort_start
    report.first_day.in_time_zone(report.zone)
  end

  # As propostas paradas, só com ids, valores e datas; o título entra só na resposta da API (Analysis).
  def stalled
    list = Crm::MetaAds::Panel::Action.stalled(report.cohort.cards, @now)
    {
      count: list.size, value: list.sum(&:value).round(2), days: Crm::MetaAds::Panel::Action::STALLED_AFTER.in_days.to_i,
      ad_name: Crm::MetaAds::Panel::Action.top_ad_name(list, report.ads),
      cards: list.first(Crm::MetaAds::Panel::Action::STALLED_LIST).map do |card|
        { id: card.id, value: card.value, conversation_id: card.conversation_id, waiting_since: card.waiting_since }
      end
    }
  end

  def response
    Crm::MetaAds::Panel::ResponseTime.new(account_id: @connection.account_id, range: cohort_start..@now).payload
  end

  def ctr(totals)
    return if totals[:impressions].zero?

    totals[:link_clicks].to_f / totals[:impressions]
  end

  def cpm(totals)
    return if totals[:impressions].zero?

    totals[:spend] / totals[:impressions] * 1000
  end

  def ratio(numerator, denominator)
    return if denominator.to_f.zero?

    (numerator.to_f / denominator).round(2)
  end
end
