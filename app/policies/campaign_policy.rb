class CampaignPolicy < ApplicationPolicy
  def index?
    @account_user.permission_granted?('campaign_view')
  end

  def update?
    @account_user.permission_granted?('campaign_manage')
  end

  def show?
    @account_user.permission_granted?('campaign_view')
  end

  def create?
    @account_user.permission_granted?('campaign_manage')
  end

  def destroy?
    @account_user.permission_granted?('campaign_manage')
  end
end
