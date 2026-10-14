# #1461 — quem vê um lembrete sem card (só no calendário ou de um cliente sem negócio): quem marcou, quem recebe
# (pessoa escolhida, time, responsável) e o administrador. Com card, vale o acesso do card (Pundit + acesso por funil).
# Serve a crm_follow_ups e a crm_follow_up_series (as duas têm created_by_id e as colunas de quem recebe).
class Crm::FollowUps::StandaloneVisibility
  def initialize(user:, account:, account_user:)
    @user = user
    @account = account
    @account_user = account_user
  end

  def apply(relation)
    return relation if @account_user&.administrator?
    return relation.none if @user.nil?

    table = relation.klass.quoted_table_name
    conditions = ["#{table}.created_by_id = :user_id", "#{table}.recipient_user_ids @> ARRAY[:user_id]::bigint[]"]
    conditions << "#{table}.assignee_id = :user_id" if relation.klass.column_names.include?('assignee_id')
    conditions << "#{table}.recipient_team_id IN (:team_ids)" if team_ids.any?
    relation.where(conditions.join(' OR '), user_id: @user.id, team_ids: team_ids)
  end

  private

  def team_ids
    @team_ids ||= TeamMember.joins(:team).where(user_id: @user.id, teams: { account_id: @account.id }).pluck(:team_id)
  end
end
