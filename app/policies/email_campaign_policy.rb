class EmailCampaignPolicy < ApplicationPolicy
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
    manage_own?
  end

  def destroy?
    manage_own?
  end

  def send_now?
    send_own?
  end

  def schedule?
    send_own?
  end

  def pause?
    manage_own?
  end

  def resume?
    send_own?
  end

  def reevaluate?
    manage_own?
  end

  def recheck?
    manage_own?
  end

  def cancel?
    manage_own?
  end

  def duplicate?
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

  # Sending is its own key (#1898): who only builds leaves the campaign ready for someone else.
  def send_own?
    permission_granted?('campaign_send') && own_account?
  end

  def own_account?
    record.account_id == account.id
  end

  def permission_granted?(key)
    account_user&.permission_granted?(key)
  end
end
