class Api::V1::Accounts::Autonomia::Agents::ChannelsController < Api::V1::Accounts::Autonomia::BaseController
  before_action :fetch_agent
  before_action :fetch_inbox, only: [:create, :destroy]

  # Lista os vínculos do agente + inboxes elegíveis da conta (para o seletor de canal).
  def index
    @agent_inboxes = @agent.agent_inboxes.includes(:inbox).order(created_at: :desc)
    @eligible_inboxes = eligible_inboxes
  end

  def create
    result = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inbox: @inbox).perform(connect: true)
    return render_unprocessable(connector_error(result.error)) unless result.success?

    @agent_inbox = result.agent_inbox
    @agent_inboxes = @agent.agent_inboxes.includes(:inbox).order(created_at: :desc)
    @eligible_inboxes = eligible_inboxes
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
end
