class SlaPolicyPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.permission_granted?('sla_manage')
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.permission_granted?('sla_manage')
  end

  def destroy?
    @account_user.permission_granted?('sla_manage')
  end
end
