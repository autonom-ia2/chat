class AgentCapacityPolicyPolicy < ApplicationPolicy
  def index?
    allowed?
  end

  def create?
    allowed?
  end

  def show?
    allowed?
  end

  def update?
    allowed?
  end

  def destroy?
    allowed?
  end

  private

  # Funções personalizadas, lote 3 (#1797): administrador ou cargo com `assignment_manage` (OSS: administrator?).
  def allowed?
    @account_user&.permission_granted?('assignment_manage') || false
  end
end
