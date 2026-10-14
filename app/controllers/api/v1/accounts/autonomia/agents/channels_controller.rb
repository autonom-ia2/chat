class Api::V1::Accounts::Autonomia::Agents::ChannelsController < Api::V1::Accounts::Autonomia::BaseController
  PAPEL_AREA = 'area'.freeze

  before_action :fetch_agent
  before_action :fetch_inbox, only: [:create, :destroy]

  # Lista os vínculos ativos do agente + inboxes elegíveis da conta (para o seletor de canal).
  # #1433: a área desmarcada fica arquivada (deleted_at) e não é canal; cada vínculo diz o papel.
  def index
    load_index
  end

  # `ativar: true` (#1366) — "Começar a atender neste canal": liga o agente parado junto com o vínculo.
  # `papel: 'area'` (#1433, tema 13) — "agente da equipe": entra na caixa como área (recebe quando alguém passa) e já
  # liga, pelo Autonomia::Agents::Areas. Só com a Fase 2 ligada na conta.
  def create
    return create_area if params[:papel] == PAPEL_AREA

    ativar = ActiveModel::Type::Boolean.new.cast(params[:ativar]) == true
    result = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inbox: @inbox, ativar: ativar).perform(connect: true)
    return render_unprocessable(connector_error(result.error)) unless result.success?

    @agent_inbox = result.agent_inbox
    load_index
    render :index, status: :created
  end

  def destroy
    result = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inbox: @inbox).perform(connect: false)
    return render_unprocessable(connector_error(result.error)) unless result.success?

    head :no_content
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def load_index
    @agent_inboxes = @agent.agent_inboxes.kept.includes(:inbox).order(created_at: :desc)
    @eligible_inboxes = eligible_inboxes
  end

  # As recusas previsíveis respondem antes, com o motivo; o Areas confere de novo com agente e caixa travados.
  def create_area
    recusa = recusa_de_area
    return render_unprocessable(area_error(recusa)) if recusa

    @agent_inbox = ::Autonomia::Agents::Areas.vincular!(agent: @agent, inbox: @inbox, ativar: true)
    load_index
    render :index, status: :created
  rescue ::Autonomia::Agents::Areas::AgenteInterno, ::Autonomia::Agents::Areas::AgenteDeSistema
    render_unprocessable(area_error(:agent_internal))
  rescue ActiveRecord::RecordInvalid
    render_unprocessable(area_error(:generic))
  end

  def recusa_de_area
    return :fase2_off unless ::Autonomia::Agents::Fase2.ligada?(Current.account)
    return :agent_internal if @agent.actuation_internal?
    return :already_linked if ::Autonomia::Agents::AgentInbox.kept.exists?(autonomia_agent_id: @agent.id, inbox_id: @inbox.id)

    :sem_principal unless principal_atendendo?
  end

  # A caixa tem porta ativa (vínculo kept de papel porta) cujo agente está atendendo.
  def principal_atendendo?
    porta = ::Autonomia::Agents::AgentInbox.kept.porta.includes(:agent).find_by(inbox_id: @inbox.id)
    porta.present? && porta.agent.operating?
  end

  # Inboxes da conta que ainda não têm nenhum bot (nem webhook/Gabriela, nem agente nativo).
  def eligible_inboxes
    connected_ids = ::Autonomia::Agents::AgentInbox.kept.where(account: Current.account).pluck(:inbox_id)
    Current.account.inboxes
           .where.missing(:agent_bot_inbox)
           .where.not(id: connected_ids)
  end

  def connector_error(code)
    I18n.t("autonomia.agents.operate.connect_errors.#{code}",
           default: I18n.t('autonomia.agents.operate.connect_errors.generic'))
  end

  def area_error(code)
    I18n.t("autonomia.agents.operate.area_errors.#{code}", nome: @agent.name, canal: @inbox.name)
  end
end
