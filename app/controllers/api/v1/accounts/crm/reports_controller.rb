class Api::V1::Accounts::Crm::ReportsController < Api::V1::Accounts::Crm::BaseController
  before_action :authorize_reports
  before_action :ensure_visible_pipeline, except: :pipelines

  def pipelines
    options = report_pipelines.order(:position, :id).map do |pipeline|
      { id: pipeline.id, name: pipeline.name, is_default: pipeline.is_default }
    end
    render json: { payload: options }
  end

  def summary
    render_report(::Crm::Reports::Summary)
  end

  def funnel
    render_report(::Crm::Reports::Funnel)
  end

  # #2000: `todos_os_funis` soma os funis que a pessoa enxerga (a frase da Gestão de IA). Só este relatório o lê.
  def ai_vs_human
    render_report(::Crm::Reports::AiVsHuman, params.permit(:todos_os_funis))
  end

  def throughput
    render_report(::Crm::Reports::Throughput)
  end

  def follow_ups
    render_report(::Crm::Reports::FollowUps)
  end

  def workload
    render_report(::Crm::Reports::Workload)
  end

  def meetings
    unless Crm::Config.calendar_meetings_enabled?(Current.account)
      payload = ::Crm::Reports::Meetings.new(account: Current.account, params: report_params).empty_payload
      return render json: { payload: payload }
    end

    render_report(::Crm::Reports::Meetings)
  end

  private

  def authorize_reports
    authorize %i[crm report], :view?
  end

  # Quem tem acesso por funil e não enxerga funil nenhum fica sem relatório: sem funil, alguns relatórios somariam a
  # conta inteira.
  def render_report(builder_class, extras = {})
    return render json: { payload: nil } if visible_pipelines.restricted? && report_pipelines.none?

    payload = builder_class.new(account: Current.account, params: report_params.merge(extras), pipelines: report_pipelines,
                                value_visible: ::Crm::ValorDeVenda.ve?(Current.account_user)).perform
    render json: { payload: payload }
  end

  # Acesso por funil (#1148, PR D): o painel só mostra os funis da pessoa; pedir o relatório de outro funil é 404.
  def ensure_visible_pipeline
    return if params[:pipeline_id].blank? || !visible_pipelines.restricted?

    report_pipelines.find(params[:pipeline_id])
  end

  def report_pipelines
    @report_pipelines ||= visible_pipelines.apply_to_reports(Current.account.crm_pipelines.active)
  end

  def visible_pipelines
    @visible_pipelines ||= Crm::Access::VisiblePipelines.new(user: Current.user, account: Current.account,
                                                             account_user: Current.account_user)
  end

  def report_params
    params.permit(:pipeline_id, :since, :until, :group_by)
  end
end
