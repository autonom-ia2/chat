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

  # Públicos (#992): choosing columns and wiring message variables are part of building a campaign.
  def columns?
    permission_granted?('campaign_manage')
  end

  # #998: the "Criar e ligar" switch follows the import permission (PRD §4).
  def companies?
    permission_granted?('campaign_manage')
  end

  def variable_suggestions?
    permission_granted?('campaign_manage')
  end

  def variable_coverage?
    permission_granted?('campaign_manage')
  end

  # #1005 (J5): turning an audience channel on or off changes who a campaign can reach.
  def channels?
    permission_granted?('campaign_manage')
  end

  # #993 (B5): masked contact and reason only, like the error report a viewer already sees.
  def problem_rows?
    permission_granted?('campaign_view')
  end

  # #993: a real name and values for the message preview, part of building a campaign.
  def sample_contact?
    permission_granted?('campaign_manage')
  end

  private

  def permission_granted?(key)
    @account_user.permission_granted?(key)
  end
end
