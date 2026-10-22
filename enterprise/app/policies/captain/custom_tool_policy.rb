class Captain::CustomToolPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  # A tool calls an outside endpoint with the account's credentials (#2027): admin or integration_manage.
  def create?
    integration_manage?
  end

  def test?
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
