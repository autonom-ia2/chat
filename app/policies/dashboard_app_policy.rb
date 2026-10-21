class DashboardAppPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  # Agents keep using the apps in the conversation; adding or changing one is admin or integration_manage (#2027).
  def create?
    integration_manage?
  end

  def update?
    integration_manage?
  end

  def destroy?
    integration_manage?
  end

  private

  def integration_manage?
    @account_user.permission_granted?('integration_manage')
  end
end
