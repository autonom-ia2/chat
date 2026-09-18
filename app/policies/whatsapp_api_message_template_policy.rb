class WhatsappApiMessageTemplatePolicy < ApplicationPolicy
  def index?
    @account_user.permission_granted?('campaign_view')
  end

  def create?
    @account_user.permission_granted?('campaign_manage')
  end

  def update?
    @account_user.permission_granted?('campaign_manage')
  end

  def destroy?
    @account_user.permission_granted?('campaign_manage')
  end
end
