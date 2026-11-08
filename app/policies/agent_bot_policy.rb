class AgentBotPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  # A bot points an outgoing URL that receives the conversations (#2027): admin or integration_manage.
  def update?
    integration_manage?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    integration_manage?
  end

  def destroy?
    integration_manage?
  end

  def avatar?
    integration_manage?
  end

  # The token and the secret are issued by the platform (#2027): admin or token_manage.
  def reset_access_token?
    token_manage?
  end

  def reset_secret?
    token_manage?
  end

  private

  def integration_manage?
    @account_user.permission_granted?('integration_manage')
  end

  def token_manage?
    @account_user.permission_granted?('token_manage')
  end
end
