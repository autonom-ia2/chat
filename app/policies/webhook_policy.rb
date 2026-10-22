# Webhooks send the account's conversations out (#2027): admin or integration_manage.
class WebhookPolicy < ApplicationPolicy
  def index?
    integration_manage?
  end

  def update?
    integration_manage?
  end

  def destroy?
    integration_manage?
  end

  def create?
    integration_manage?
  end

  private

  def integration_manage?
    @account_user.permission_granted?('integration_manage')
  end
end
