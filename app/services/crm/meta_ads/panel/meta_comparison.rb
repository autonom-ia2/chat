# "Quanto confiar", Meta × nós (#1110, F5, D5.8): o número que a Meta diz ao lado do que nós contamos, no período
# do painel e até ontem (o gasto de hoje ainda é parcial, e os nossos toques entram na hora).
#
# Uma linha por destino marcado na conexão, WhatsApp primeiro. A Meta não diz em que destino cada anúncio está;
# cada métrica só existe em anúncio daquele destino, então a linha soma a conta inteira sem contar nada duas vezes:
# - `whatsapp`: `conversations_started` (conversas iniciadas, 7 dias por clique) × as conversas cujo primeiro
#   toque do período veio do WhatsApp;
# - `messaging` (#2521): a mesma métrica, só dos anúncios cujo conjunto leva ao Messenger ou ao Direct
#   (Panel::AdDestinations#messenger_or_direct?), × as conversas cujo primeiro toque veio do Messenger ou do Direct.
#   Esses anúncios saem da linha do WhatsApp; o de conjunto ainda não lido fica nela. Não depende de destino marcado na
#   conexão: aparece quando há número;
# - `site`: os leads do Pixel (`offsite_conversion.fb_pixel_lead`, em `actions`) × as conversas cujo primeiro
#   toque veio da ponte do site. As visitas à página (`landing_page_view`) vão junto, só de contexto. É a linha
#   que a Placement tem: os anúncios dela levam ao site e não têm conversa contada pela Meta (gate G1).
#
# Linha sem número da Meta e sem conversa nossa não aparece; sem nenhuma linha, nil. `explanation` é decidida
# aqui, nunca pela IA. #2344: "batem" (`close`) só com os dois lados acima de zero e a diferença de até 10% do maior;
# uma tolerância absoluta ficava maior que os próprios números (2 × 0 "batia"). Meta com número e nós com zero é
# `ours_none`: nenhuma conversa chegou com a marca do anúncio. Meta com zero e nós com número é `meta_none` (cada um conta
# de um jeito; vale o nosso), menos quando a Meta não mandou número nenhum no período: aí o aviso geral `no_meta_data`
# já explica, e a linha fica sem frase.
class Crm::MetaAds::Panel::MetaComparison
  LEAD_ACTION = 'offsite_conversion.fb_pixel_lead'.freeze
  VISIT_ACTION = 'landing_page_view'.freeze
  CLOSE_SHARE = 0.10
  ACTION_SQL = 'jsonb_array_elements(crm_meta_ad_insights_daily.actions) AS action'.freeze
  # Com a janela fixa, cada ação traz o valor nela; sem ele, o valor padrão (como Insights::Writer#conversations).
  ACTION_VALUE_SQL = Arel.sql("COALESCE(action->>'#{Crm::MetaAds::Insights::Writer::ATTRIBUTION_WINDOW}', action->>'value')::numeric")

  def initialize(connection, report)
    @connection = connection
    @report = report
  end

  def payload
    rows = [whatsapp_row, messaging_row, site_row].compact
    return if rows.empty?

    no_meta = rows.none? { |row| row[:meta].positive? } && insights.sum(:spend).positive?
    return { days: @report.days, until: until_day, rows: rows, explanation: nil } unless no_meta

    { days: @report.days, until: until_day, rows: without_meta_none(rows), explanation: 'no_meta_data' }
  end

  private

  # O aviso geral já diz que a Meta não mandou número: a linha não repete "cada um conta de um jeito".
  def without_meta_none(rows)
    rows.map { |row| row[:explanation] == 'meta_none' ? row.merge(explanation: nil) : row }
  end

  def destination?(key)
    @connection.destinations_payload[key]
  end

  def whatsapp_row
    return unless destination?('whatsapp')

    row('whatsapp', insights.sum(:conversations_started).to_i - messaging_started, ours['whatsapp'].to_i)
  end

  def messaging_row
    row('messaging', messaging_started, ours['messenger'].to_i + ours['instagram'].to_i)
  end

  def messaging_started
    @messaging_started ||= begin
      destinations = Crm::MetaAds::Panel::AdDestinations.new(@connection.account_id, insights)
      started = insights.where(conversations_started: 1..).group(:ad_id).sum(:conversations_started)
      started.sum { |ad_id, value| destinations.messenger_or_direct?(ad_id) ? value.to_i : 0 }
    end
  end

  def site_row
    return unless destination?('site')

    row('site', actions[LEAD_ACTION].to_i, ours['site'].to_i)&.merge(meta_visits: actions[VISIT_ACTION].to_i)
  end

  def row(destination, meta, ours)
    return if meta.zero? && ours.zero?

    difference = ours - meta
    { destination: destination, meta: meta, ours: ours, difference: difference, explanation: explanation(meta, difference) }
  end

  def explanation(meta, difference)
    ours = meta + difference
    return 'meta_none' if meta.zero?
    return 'ours_none' if ours.zero?
    return 'close' if difference.abs <= [meta, ours].max * CLOSE_SHARE

    difference.negative? ? 'meta_higher' : 'ours_higher'
  end

  # Até ontem (o número da Meta de hoje ainda não fechou), ou até o fim do período que já acabou (mês passado).
  def until_day
    [@report.today - 1, @report.last_day].min
  end

  def insights
    Crm::MetaAdInsightDaily.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id,
                                  date: @report.first_day..until_day)
  end

  # { action_type => total } das duas ações do site, numa consulta.
  def actions
    @actions ||= insights.joins("CROSS JOIN LATERAL #{ACTION_SQL}")
                         .where("action->>'action_type' IN (?)", [LEAD_ACTION, VISIT_ACTION])
                         .group(Arel.sql("action->>'action_type'")).sum(ACTION_VALUE_SQL)
  end

  # { origin => conversas }: cada conversa conta uma vez, pela origem do primeiro toque dela no período.
  def ours
    @ours ||= Crm::MetaAdLink.where(account_id: @connection.account_id, touched_at: touch_range)
                             .where(ad_account_id: [@connection.ad_account_id, nil])
                             .order(:conversation_id, :touched_at)
                             .pluck(Arel.sql('DISTINCT ON (conversation_id) origin')).tally
  end

  def touch_range
    @report.first_day.in_time_zone(@report.zone)...(until_day + 1).in_time_zone(@report.zone)
  end
end
