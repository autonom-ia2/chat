module Enterprise::Api::V1::Accounts::AgentsController
  def create
    role_id = requested_custom_role_id
    super
    return if @agent.blank?

    associate_agent_with_custom_role(role_id)
  end

  def update
    role_id = requested_custom_role_id
    super
    associate_agent_with_custom_role(role_id)
  end

  private

  # Resolved before the agent is saved, so an unknown role changes nothing (#1157).
  # Only a role of this account; another id raises RecordNotFound (404).
  def requested_custom_role_id
    return if custom_role_id_param.blank?

    Current.account.custom_roles.find(custom_role_id_param).id
  end

  def associate_agent_with_custom_role(role_id)
    # Fork: create may answer with a pending Autonomia invitation and no local agent record.
    return if @agent.blank?
    # An update that does not mention the role keeps it (#1157). Before, any PATCH without the
    # field (name, availability, an integration) silently removed the agent's role.
    return unless custom_role_id_sent?
    # Custom roles are a premium feature; block assigning one when the feature is disabled,
    # but still allow clearing a stale custom_role_id left over from before a downgrade.
    return if role_id.present? && !Current.account.feature_enabled?('custom_roles')

    @agent.current_account_user.update!(custom_role_id: role_id)
  end

  def custom_role_id_sent?
    params.key?(:custom_role_id) || (params[:agent].respond_to?(:key?) && params[:agent].key?(:custom_role_id))
  end

  # Fork: accept the nested `agent[custom_role_id]` shape as well as the top-level param.
  def custom_role_id_param
    params.dig(:agent, :custom_role_id).presence || params[:custom_role_id]
  end
end
