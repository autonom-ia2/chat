class Api::V1::Accounts::Autonomia::Agents::HandoffTargetsController < Api::V1::Accounts::Autonomia::BaseController
  before_action :require_manage_permission
  before_action :fetch_agent

  def index
    inboxes = @agent.agent_inboxes.kept.includes(:inbox).map(&:inbox)
    members = common_assignable_members(inboxes)
    teams = Current.account.teams.order(:name).map { |team| { id: team.id, name: team.name } }

    render json: { members: members.map { |member| { id: member.id, name: member.name } }, teams: teams }
  end

  private

  def require_manage_permission
    check_permission_granted!('autonomia_manage')
  end

  def fetch_agent
    @agent = agents_scope.find(params[:id])
  end

  def common_assignable_members(inboxes)
    return [] if inboxes.empty?

    members_by_id = inboxes.map { |inbox| inbox.assignable_agents.index_by(&:id) }
    common_ids = members_by_id.drop(1).reduce(members_by_id.first.keys) { |ids, members| ids & members.keys }
    members_by_id.first.values_at(*common_ids).compact.sort_by { |member| member.name.to_s.downcase }
  end
end
