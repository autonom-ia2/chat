# #1931: custom_role_manage builds roles; people_manage also reads them, to pick one when adding someone. What a
# person may build or hand out is checked by CustomRoles::GrantGuard.
class CustomRolePolicy < ApplicationPolicy
  def index?
    read?
  end

  def update?
    manage?
  end

  def show?
    read?
  end

  def create?
    manage?
  end

  def destroy?
    manage?
  end

  private

  def read?
    manage? || @account_user.permission_granted?('people_manage')
  end

  def manage?
    @account_user.permission_granted?('custom_role_manage')
  end
end
