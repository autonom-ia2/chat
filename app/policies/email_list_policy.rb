# Listas de e-mail (G52, #2760): ver com campaign_view, criar, renomear e apagar com campaign_manage. No OSS as duas
# chaves respondem administrator?; no EE contam as da função personalizada.
class EmailListPolicy < ApplicationPolicy
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

  private

  def own_account?
    record.account_id == account.id
  end

  def permission_granted?(key)
    account_user&.permission_granted?(key)
  end
end
