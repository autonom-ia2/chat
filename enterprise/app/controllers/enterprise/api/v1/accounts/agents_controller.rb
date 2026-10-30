module Enterprise::Api::V1::Accounts::AgentsController
  def create
    super
    return if @agent.blank?

    associate_agent_with_custom_role
  end

  # Name, role and custom role change together or not at all (#1931).
  def update
    ActiveRecord::Base.transaction do
      super
      associate_agent_with_custom_role
    end
  end

  private

  def guard_new_agent!
    super
    custom_role_guard.role_to_grant!(custom_role_id_param)
  end

  # Someone whose current role is out of the giver's reach is not edited at all, as the screen shows (#1931).
  # Clearing or switching the custom role changes access: one's own stays out of reach, and the new role must be within
  # the giver's reach too. Runs before any write.
  def guard_agent_update!
    super
    account_user = @agent.current_account_user
    custom_role_guard.reach_current!(account_user)
    return unless custom_role_id_given?
    return if custom_role_id_param.to_s == account_user.custom_role_id.to_s

    access_guard.touch_access!(account_user)
    return custom_role_guard.role_to_grant!(custom_role_id_param) if custom_role_id_param.present?

    refuse_no_role_out_of_reach
  end

  # Taking someone out of their role leaves them with the "Sem função" keys, which the giver must reach (#2317). The
  # refusal carries the reason code of /custom_roles, so the role screen can say why.
  def refuse_no_role_out_of_reach
    custom_role_guard.no_role!
  rescue CustomRoles::GrantGuard::Denied => e
    log_handled_error(e)
    render json: { error: e.code, message: I18n.t("errors.custom_role.#{e.code}") }, status: :unauthorized
  end

  def guard_agent_removal!
    super
    custom_role_guard.reach_current!(@agent.current_account_user)
  end

  def custom_role_guard
    @custom_role_guard ||= CustomRoles::GrantGuard.new(actor: Current.account_user)
  end

  def associate_agent_with_custom_role
    # Fork: create may answer with a pending Autonomia invitation and no local agent record.
    return if @agent.blank?
    # An update that does not mention the custom role (e.g. only the name) keeps it. It used to clear it, which turned
    # the person into a plain agent, who often sees more (#1931).
    return unless custom_role_id_given?
    # Custom roles are a premium feature; block assigning one when the feature is disabled,
    # but still allow clearing a stale custom_role_id left over from before a downgrade.
    return if custom_role_id_param.present? && !Current.account.feature_enabled?('custom_roles')

    @agent.current_account_user.update!(custom_role_id: custom_role_id_param)
  end

  def custom_role_id_given?
    params[:agent]&.key?(:custom_role_id) || params.key?(:custom_role_id)
  end

  # Fork: accept the nested `agent[custom_role_id]` shape as well as the top-level param. Only a single id: a list or a
  # hash is refused instead of reaching `find` (#1931).
  def custom_role_id_param
    value = params.dig(:agent, :custom_role_id).presence || params[:custom_role_id]
    raise Pundit::NotAuthorizedError unless value.nil? || value.is_a?(String) || value.is_a?(Integer)

    value
  end
end
