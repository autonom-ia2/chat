class Api::V1::Accounts::Autonomia::Agents::AnalyticsController < Api::V1::Accounts::Autonomia::BaseController
  # Lista clicável da aba Desempenho: as N conversas mais recentes por resultado (sem paginação).
  DRILLDOWN_LIMIT = 50

  before_action :fetch_agent

  def index
    @analytics = ::Autonomia::Agents::Analytics.new(agent: @agent, range: params[:range]).call
  end

  # #284 — conversas por resultado (metric = handled | resolved_without_human | handed_off | reopened |
  # wrong_replies). Mesmo envelope { meta, payload } e serializer do drilldown dos relatórios, para a UI
  # reusar o card de conversa. O total conta o escopo já filtrado por permissão antes do limite; a
  # busca limitada devolve N+1 linhas para manter o payload pequeno e derivar `has_more`.
  def conversations
    metric = params[:metric].to_s
    return render_unknown_metric unless valid_metric?(metric)

    analytics = ::Autonomia::Agents::Analytics.new(agent: @agent, range: params[:range])
    return render_wrong_reply_reports(analytics) if metric == 'wrong_replies'

    render_conversation_drilldown(analytics, metric)
  end

  private

  def render_conversation_drilldown(analytics, metric)
    visible = visible_conversations(analytics, metric)
    visible_count = visible.count
    has_hidden = analytics.outcome_scope(metric).where.not(id: visible.select(:id)).exists?
    fetched = visible
              .includes(:assignee, :contact, :inbox)
              .order(last_activity_at: :desc)
              .limit(DRILLDOWN_LIMIT + 1)
              .to_a
    records = fetched.first(DRILLDOWN_LIMIT)
    serializer = ::V2::Reports::DrilldownRecordSerializer.new(Current.account, metric, false, records)

    render json: {
      meta: { metric: metric, range: analytics.range, limit: DRILLDOWN_LIMIT, count: visible_count,
              has_hidden: has_hidden, has_more: fetched.size > DRILLDOWN_LIMIT },
      payload: records.map { |record| serializer.serialize(record) }
    }
  end

  def render_wrong_reply_reports(analytics)
    reports = analytics.wrong_reply_report_scope
    visible = reports.where(conversation_id: visible_conversations(analytics, 'wrong_replies').select(:id))
    total_count = reports.count
    visible_count = visible.count
    records = visible.includes(message: [:sender, { conversation: %i[assignee contact inbox] }])
                     .order(created_at: :desc, id: :desc).limit(DRILLDOWN_LIMIT + 1).to_a
    conversation_serializer = ::V2::Reports::DrilldownRecordSerializer.new(
      Current.account, 'wrong_replies', false, records.map(&:message)
    )
    render json: {
      meta: { metric: 'wrong_replies', range: analytics.range, limit: DRILLDOWN_LIMIT,
              count: visible_count, total_count: total_count, hidden_count: total_count - visible_count,
              has_hidden: total_count > visible_count, has_more: visible_count > DRILLDOWN_LIMIT },
      payload: records.first(DRILLDOWN_LIMIT).map do |report|
        wrong_reply_report_payload(report, conversation_serializer)
      end
    }
  end

  def wrong_reply_report_payload(report, conversation_serializer)
    {
      report_id: report.id, conversation_id: report.conversation_id, message_id: report.message_id,
      report_reason: report.report_reason,
      reason_label: I18n.t("autonomia.agents.report_reasons.#{report.report_reason}", locale: current_account.locale),
      suggested_answer: report.description.presence, message: report.message.content, reported_at: report.created_at,
      conversation: conversation_serializer.serialize(report.message).fetch(:conversation)
    }
  end

  def visible_conversations(analytics, metric)
    Conversations::PermissionFilterService.new(
      analytics.outcome_scope(metric), Current.user, Current.account
    ).perform
  end

  def valid_metric?(metric)
    ::Autonomia::Agents::Analytics::OUTCOME_METRICS.include?(metric)
  end

  def render_unknown_metric
    render_unprocessable(
      I18n.t('autonomia.agents.errors.unknown_metric', locale: current_account.locale),
      code: 'unknown_metric'
    )
  end

  def fetch_agent
    @agent = agents_scope.find(params[:id]) # agents_scope = conta corrente -> isolamento
  end
end
