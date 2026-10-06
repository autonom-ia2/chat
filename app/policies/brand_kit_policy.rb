# Kits de marca (#1076): ver com campaign_view, mudar com campaign_manage (funções personalizadas).
class BrandKitPolicy < ApplicationPolicy
  def index?
    permission_granted?('campaign_view')
  end

  def show?
    permission_granted?('campaign_view') && own_account?
  end

  def create?
    permission_granted?('campaign_manage')
  end

  def update?
    permission_granted?('campaign_manage') && own_account?
  end

  def destroy?
    update?
  end

  def set_default?
    update?
  end

  private

  def own_account?
    record.account_id == account.id
  end

  def permission_granted?(key)
    account_user&.permission_granted?(key)
  end
end
