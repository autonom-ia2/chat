# Campaign list imports write contacts and labels, and the source file carries personal data:
# only listing and reports are read-level (campaign_view); everything else needs campaign_manage.
class CampaignImportPolicy < ApplicationPolicy
  def index?
    permission_granted?('campaign_view')
  end

  def show?
    permission_granted?('campaign_view')
  end

  def report?
    permission_granted?('campaign_view')
  end

  def errors?
    permission_granted?('campaign_view')
  end

  def create?
    permission_granted?('campaign_manage')
  end

  def destroy?
    permission_granted?('campaign_manage')
  end

  def validate?
    permission_granted?('campaign_manage')
  end

  def preview_labels?
    permission_granted?('campaign_manage')
  end

  def confirm?
    permission_granted?('campaign_manage')
  end

  def undo_labels?
    permission_granted?('campaign_manage')
  end

  def download?
    permission_granted?('campaign_manage')
  end

  private

  def permission_granted?(key)
    @account_user.permission_granted?(key)
  end
end
