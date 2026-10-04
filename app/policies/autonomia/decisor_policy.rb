# Decisor (#858): faz parte das automações, então segue as chaves delas. Ver exige automation_view;
# criar, mudar, testar (gasta o Jev), confirmar exemplo e resolver caso exigem automation_manage.
# Agente comum sem função personalizada fica de fora, como nas automações.
class Autonomia::DecisorPolicy < ApplicationPolicy
  def index?
    permission_granted?('automation_view')
  end

  def show?
    permission_granted?('automation_view')
  end

  def decisoes?
    permission_granted?('automation_view')
  end

  def create?
    permission_granted?('automation_manage')
  end

  def update?
    permission_granted?('automation_manage')
  end

  def destroy?
    permission_granted?('automation_manage')
  end

  def teste?
    permission_granted?('automation_manage')
  end

  def exemplos?
    permission_granted?('automation_manage')
  end

  def resolver?
    permission_granted?('automation_manage')
  end

  private

  def permission_granted?(key)
    account_user&.permission_granted?(key) || false
  end
end
