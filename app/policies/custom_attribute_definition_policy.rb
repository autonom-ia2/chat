class CustomAttributeDefinitionPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.permission_granted?('attribute_manage')
  end

  def update?
    @account_user.permission_granted?('attribute_manage')
  end

  def destroy?
    @account_user.permission_granted?('attribute_manage')
  end
end
