class EmailCampaignTemplatePolicy < ApplicationPolicy
  def index?
    permission_granted?('campaign_view')
  end

  def show?
    # Own-account templates and shared GLOBAL templates (account_id IS NULL) are both viewable.
    permission_granted?('campaign_view') && (record.account_id.nil? || record.account_id == account.id)
  end

  def create?
    permission_granted?('campaign_manage')
  end

  def destroy?
    # Global templates are read-only; only own-account templates can be deleted.
    permission_granted?('campaign_manage') && record.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: [account.id, nil])
    end
  end

  private

  def permission_granted?(key)
    account_user&.permission_granted?(key)
  end
end
