# "Quanto confiar", Meta × nós (#1110, F5, D5.8): o número que a Meta diz ao lado do que nós contamos, no período
# do painel e até ontem (o gasto de hoje ainda é parcial, e os nossos toques entram na hora).
#
# Uma linha por destino marcado na conexão, WhatsApp primeiro. A Meta não diz em que destino cada anúncio está;
# cada métrica só existe em anúncio daquele destino, então a linha soma a conta inteira sem contar nada duas vezes:
# - `whatsapp`: `conversations_started` (conversas iniciadas, 7 dias por clique) × as conversas cujo primeiro
#   toque do período veio do WhatsApp;
# - `site`: os leads do Pixel (`offsite_conversion.fb_pixel_lead`, em `actions`) × as conversas cujo primeiro
#   toque veio da ponte do site. As visitas à página (`landing_page_view`) vão junto, só de contexto. É a linha
#   que a Placement tem: os anúncios dela levam ao site e não têm conversa contada pela Meta (gate G1).
#
# Linha sem número da Meta e sem conversa nossa não aparece; sem nenhuma linha, nil. `explanation` é decidida
# aqui, nunca pela IA.
class Crm::MetaAds::Panel::MetaComparison
  LEAD_ACTION = 'offsite_conversion.fb_pixel_lead'.freeze
  VISIT_ACTION = 'landing_page_view'.freeze
  CLOSE_MIN = 2
  CLOSE_SHARE = 0.10
  ACTION_SQL = 'jsonb_array_elements(crm_meta_ad_insights_daily.actions) AS action'.freeze
  # Com a janela fixa, cada ação traz o valor nela; sem ele, o valor padrão (como Insights::Writer#conversations).
  ACTION_VALUE_SQL = Arel.sql("COALESCE(action->>'#{Crm::MetaAds::Insights::Writer::ATTRIBUTION_WINDOW}', action->>'value')::numeric")

  def initialize(connection, report)
    @connection = connection
    @report = report
  end

  def payload
    rows = [whatsapp_row, site_row].compact
    return if rows.empty?

    no_meta = rows.none? { |row| row[:meta].positive? } && insights.sum(:spend).positive?
    { days: @report.days, until: until_day, rows: rows, explanation: no_meta ? 'no_meta_data' : nil }
  end

  private

  def destination?(key)
    @connection.destinations_payload[key]
  end

  def whatsapp_row
    return unless destination?('whatsapp')

    row('whatsapp', insights.sum(:conversations_started).to_i, ours['whatsapp'].to_i)
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

  # Sem número da Meta (ainda não mandou, ou o destino não tem o dado) não há o que explicar: nil.
  def explanation(meta, difference)
    return if meta.zero?
    return 'close' if difference.abs <= [CLOSE_MIN, meta * CLOSE_SHARE].max

    difference.negative? ? 'meta_higher' : 'ours_higher'
  end

  def until_day
    @report.today - 1
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
    @report.first_day.in_time_zone(@report.zone)...@report.today.in_time_zone(@report.zone)
  end
end
