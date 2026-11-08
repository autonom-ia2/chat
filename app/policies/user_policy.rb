class UserPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    @account_user.permission_granted?('people_manage')
  end

  def update?
    @account_user.permission_granted?('people_manage')
  end

  def destroy?
    @account_user.permission_granted?('people_manage')
  end

  def bulk_create?
    @account_user.permission_granted?('people_manage')
  end
end
