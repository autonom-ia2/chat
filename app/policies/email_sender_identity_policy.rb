class EmailSenderIdentityPolicy < ApplicationPolicy
  def index?
    permission_granted?('campaign_view')
  end

  def show?
    permission_granted?('campaign_view') && own_account?
  end

  def create?
    permission_granted?('campaign_manage')
  end

  def verify?
    manage_own?
  end

  def dns_check?
    manage_own?
  end

  def destroy?
    manage_own?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end

  private

  def manage_own?
    permission_granted?('campaign_manage') && own_account?
  end

  def own_account?
    record.account_id == account.id
  end

  def permission_granted?(key)
    account_user&.permission_granted?(key)
  end
end
