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

  # Sending, scheduling and resuming (#1898). Building the campaign stays with create?/update?.
  def send_campaign?
    create? && @account_user.permission_granted?('campaign_send')
  end
end
