class LabelPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.permission_granted?('label_manage')
  end

  def show?
    @account_user.permission_granted?('label_manage')
  end

  def create?
    @account_user.permission_granted?('label_manage')
  end

  def destroy?
    @account_user.permission_granted?('label_manage')
  end
end
