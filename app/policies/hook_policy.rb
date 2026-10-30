# Connecting, changing and disconnecting an integration is admin or integration_manage (#2027); using it is open.
class HookPolicy < ApplicationPolicy
  def create?
    integration_manage?
  end

  def update?
    integration_manage?
  end

  def process_event?
    true
  end

  def destroy?
    integration_manage?
  end

  private

  def integration_manage?
    @account_user.permission_granted?('integration_manage')
  end
end
