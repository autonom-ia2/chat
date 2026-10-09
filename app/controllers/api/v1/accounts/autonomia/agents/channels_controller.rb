class Api::V1::Accounts::Autonomia::Agents::ChannelsController < Api::V1::Accounts::Autonomia::BaseController
  before_action :fetch_agent
  before_action :fetch_inbox, only: [:create, :destroy]

  # Lista os vínculos do agente + inboxes elegíveis da conta (para o seletor de canal).
  def index
    load_channel_projection
  end

  def create
    result = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inbox: @inbox).perform(connect: true)
    return render_unprocessable(connector_error(result.error), code: result.error) unless result.success?

    @agent_inbox = result.agent_inbox
    load_channel_projection
    render :index, status: :created
  end

  def destroy
    result = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inbox: @inbox).perform(connect: false)
    return render_unprocessable(connector_error(result.error), code: result.error) unless result.success?

    head :no_content
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def load_channel_projection
    @agent_inboxes = @agent.agent_inboxes.kept.includes(:inbox).order(created_at: :desc)
    @eligible_inboxes = eligible_inboxes.includes(:channel).to_a
    @occupied_inboxes = occupied_inboxes
    @has_schedule_by_inbox_id = schedule_by_inbox_id
  end

  # Inboxes da conta que ainda não têm nenhum bot (nem webhook/Gabriela, nem agente nativo).
  def eligible_inboxes
    connected_ids = ::Autonomia::Agents::AgentInbox.kept.where(account: Current.account).pluck(:inbox_id)
    Current.account.inboxes
           .where.not(id: ::AgentBotInbox.where(account: Current.account).select(:inbox_id))
           .where.not(id: connected_ids)
  end

  def occupied_inboxes
    inboxes = Current.account.inboxes.includes(:channel).to_a
    native_links = ::Autonomia::Agents::AgentInbox.kept
                                                  .where(account: Current.account)
                                                  .includes(:agent)
                                                  .index_by(&:inbox_id)
    external_bot_inbox_ids = ::AgentBotInbox.joins(:agent_bot)
                                            .where(account: Current.account)
                                            .where.not(agent_bots: { outgoing_url: [nil, ''] })
                                            .pluck(:inbox_id)

    inboxes.filter_map do |inbox|
      if (link = native_links[inbox.id])
        { inbox: inbox,
          occupied_by: { kind: 'agent', agent_id: link.agent.id, agent_name: link.agent.name } }
      elsif external_bot_inbox_ids.include?(inbox.id)
        { inbox: inbox, occupied_by: { kind: 'other_bot' } }
      end
    end
  end

  def schedule_by_inbox_id
    inbox_ids = @agent_inboxes.map(&:inbox_id) + @eligible_inboxes.map(&:id) +
                @occupied_inboxes.map { |entry| entry[:inbox].id }
    schedules = ::Crm::ServiceSchedule.where(account: Current.account, owner_type: 'Inbox', owner_id: inbox_ids)
                                      .index_by(&:owner_id)
    inboxes = @agent_inboxes.map(&:inbox) + @eligible_inboxes + @occupied_inboxes.pluck(:inbox)
    inboxes.to_h do |inbox|
      [inbox.id,
       ::Autonomia::Agents::Operate::EngagementGate.schedule?(
         inbox, service_schedule: schedules.fetch(inbox.id, nil)
       )]
    end
  end

  def connector_error(code)
    I18n.t("autonomia.agents.operate.connect_errors.#{code}",
           default: I18n.t('autonomia.agents.operate.connect_errors.generic'))
  end
end
