module EnsureCurrentAccountHelper
  private

  def current_account
    @current_account ||= ensure_current_account
    Current.account = @current_account
  end

  def ensure_current_account
    account = Account.find(params[:account_id])
    render_unauthorized('Account is suspended') and return unless account.active?

    if integration_token_account?
      account_accessible_for_integration_token?(account)
    elsif current_user
      account_accessible_for_user?(account)
    elsif @resource.is_a?(AgentBot)
      account_accessible_for_bot?(account)
    else
      render_unauthorized(I18n.t('errors.account.not_authorized'))
    end
    account
  end

  def account_accessible_for_user?(account)
    @current_account_user = account.account_users.find_by(user_id: current_user.id)
    Current.account_user = @current_account_user
    render_unauthorized(I18n.t('errors.account.not_authorized')) unless @current_account_user
  end

  def account_accessible_for_bot?(account)
    return if @resource.account_id == account.id
    return if @resource.agent_bot_inboxes.find_by(account_id: account.id)

    render_unauthorized('Bot is not authorized to access this account')
  end

  # CRM integration token (plan §3.2, B-T3). defined?-guarded so CE never sees
  # the EE-only constant. Current.account_user was already set in the auth helper.
  def integration_token_account?
    defined?(Crm::IntegrationToken) && current_integration_token.present?
  end

  def account_accessible_for_integration_token?(account)
    return if current_integration_token.account_id == account.id

    render_unauthorized('Token is not authorized to access this account')
  end
end
