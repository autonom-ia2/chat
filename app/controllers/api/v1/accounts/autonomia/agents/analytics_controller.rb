class Api::V1::Accounts::Autonomia::Agents::AnalyticsController < Api::V1::Accounts::Autonomia::BaseController
  # Lista clicável da aba Desempenho: as N conversas mais recentes por resultado (sem paginação).
  DRILLDOWN_LIMIT = 50

  before_action :fetch_agent

  def index
    @analytics = ::Autonomia::Agents::Analytics.new(agent: @agent, range: params[:range]).call
  end

  # #284 — conversas por resultado (metric = handled | resolved_without_human | handed_off | reopened |
  # wrong_replies). Mesmo envelope { meta, payload } e serializer do drilldown dos relatórios, para a UI
  # reusar o card de conversa. O escopo (pesado: subqueries em eventos/reporting_events) é avaliado UMA
  # vez: busca N+1 linhas e deriva `has_more` — sem um COUNT separado sem limit.
  def conversations
    metric = params[:metric].to_s
    return render_unprocessable('unknown metric') unless ::Autonomia::Agents::Analytics::OUTCOME_METRICS.include?(metric)

    analytics = ::Autonomia::Agents::Analytics.new(agent: @agent, range: params[:range])
    fetched = analytics.outcome_scope(metric)
                       .includes(:assignee, :contact, :inbox)
                       .order(last_activity_at: :desc)
                       .limit(DRILLDOWN_LIMIT + 1)
                       .to_a
    records = fetched.first(DRILLDOWN_LIMIT)
    serializer = ::V2::Reports::DrilldownRecordSerializer.new(Current.account, metric, false, records)

    render json: {
      meta: { metric: metric, range: analytics.range, limit: DRILLDOWN_LIMIT, count: records.size,
              has_more: fetched.size > DRILLDOWN_LIMIT },
      payload: records.map { |record| serializer.serialize(record) }
    }
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:id]) # agents_scope = conta corrente -> isolamento
  end
end
