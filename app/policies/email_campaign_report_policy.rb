class EmailCampaignReportPolicy < ApplicationPolicy
  def view?
    permission_granted?('campaign_view')
  end

  # The export carries recipient e-mails (personal data), so it needs the manage key.
  def export?
    permission_granted?('campaign_manage')
  end

  private

  def permission_granted?(key)
    account_user&.permission_granted?(key)
  end
end
