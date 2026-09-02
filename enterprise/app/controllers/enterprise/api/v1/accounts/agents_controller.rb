module Enterprise::Api::V1::Accounts::AgentsController
  def create
    super
    return if @agent.blank?

    associate_agent_with_custom_role
  end

  def update
    super
    associate_agent_with_custom_role
  end

  private

  def associate_agent_with_custom_role
    # Fork: create may answer with a pending Autonomia invitation and no local agent record.
    return if @agent.blank?
    # Custom roles are a premium feature; block assigning one when the feature is disabled,
    # but still allow clearing a stale custom_role_id left over from before a downgrade.
    return if custom_role_id_param.present? && !Current.account.feature_enabled?('custom_roles')

    @agent.current_account_user.update!(custom_role_id: custom_role_id_param)
  end

  # Fork: accept the nested `agent[custom_role_id]` shape as well as the top-level param.
  def custom_role_id_param
    params.dig(:agent, :custom_role_id).presence || params[:custom_role_id]
  end
end
