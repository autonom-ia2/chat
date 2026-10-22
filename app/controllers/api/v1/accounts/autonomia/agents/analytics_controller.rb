class Api::V1::Accounts::Autonomia::Agents::AnalyticsController < Api::V1::Accounts::Autonomia::BaseController
  # Lista clicável da aba Desempenho: as N conversas mais recentes por resultado (sem paginação).
  DRILLDOWN_LIMIT = 50
  # #2000 — as listas dos cartões da semana na página do agente: a conta única da IA (Autonomia::ContaDaIa), a mesma do
  # número do cartão (numeros_da_semana). Sempre a semana da página; o `range` não vale para elas.
  CONTA_DA_IA = { 'respondidas' => 'atendeu', 'passadas' => 'passou', 'resolvidas_sozinha' => 'resolveuSozinha' }.freeze

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
    return render_conta_da_ia(metric) if CONTA_DA_IA.key?(metric)
    return render_unprocessable('unknown metric') unless ::Autonomia::Agents::Analytics::OUTCOME_METRICS.include?(metric)

    analytics = ::Autonomia::Agents::Analytics.new(agent: @agent, range: params[:range])
    render_drilldown(metric, analytics.range, visiveis(analytics.outcome_scope(metric)))
  end

  private

  def render_conta_da_ia(metric)
    conta = ::Autonomia::ContaDaIa.new(account: Current.account, range: ::Autonomia::ContaDaIa.semana(Current.account),
                                       conversas: ::Autonomia::ContaDaIa.visiveis(user: Current.user, account: Current.account))
    render_drilldown(metric, ::Autonomia::AgentesSemanaFinder::RANGE, conta.conversas_do_agente(@agent.id, CONTA_DA_IA[metric]))
  end

  def render_drilldown(metric, range, conversas)
    fetched = conversas
              .includes(:assignee, :contact, :inbox)
              .order(last_activity_at: :desc)
              .limit(DRILLDOWN_LIMIT + 1)
              .to_a
    records = fetched.first(DRILLDOWN_LIMIT)
    serializer = ::V2::Reports::DrilldownRecordSerializer.new(Current.account, metric, false, records)

    render json: {
      meta: { metric: metric, range: range, limit: DRILLDOWN_LIMIT, count: records.size,
              has_more: fetched.size > DRILLDOWN_LIMIT },
      payload: records.map { |record| serializer.serialize(record) }
    }
  end

  # #1788: a lista abre conversas, então segue a regra da lista de conversas (caixa, funil e função). Os totais do
  # painel (index) continuam da conta.
  def visiveis(conversas)
    ::Conversations::PermissionFilterService.new(conversas, Current.user, Current.account, for_reading: true).perform
  end

  def fetch_agent
    @agent = agents_scope.find(params[:id]) # agents_scope = conta corrente -> isolamento
  end
end
