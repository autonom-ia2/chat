class WhatsappApiCampaignPolicy < ApplicationPolicy
  def index?
    @account_user.permission_granted?('campaign_view')
  end

  def show?
    @account_user.permission_granted?('campaign_view')
  end

  def create?
    @account_user.permission_granted?('campaign_manage')
  end

  def pause?
    @account_user.permission_granted?('campaign_manage')
  end

  def resume?
    @account_user.permission_granted?('campaign_manage')
  end

  def cancel?
    @account_user.permission_granted?('campaign_manage')
  end
end
