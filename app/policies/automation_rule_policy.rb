class AutomationRulePolicy < ApplicationPolicy
  def index?
    @account_user.permission_granted?('automation_view')
  end

  def create?
    @account_user.permission_granted?('automation_manage')
  end

  def show?
    @account_user.permission_granted?('automation_view')
  end

  def update?
    @account_user.permission_granted?('automation_manage')
  end

  def clone?
    @account_user.permission_granted?('automation_manage')
  end

  def destroy?
    @account_user.permission_granted?('automation_manage')
  end
end
