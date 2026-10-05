# "Excluir público" (#1005, F2/N4): deletes only the list — the import, its rows and its label
# records. Contacts, companies, conversations and labels already on contacts stay, and every
# campaign that used the audience is detached (campaign_audience_links.campaign_import_id = NULL)
# so a completed campaign keeps its recipients and results.
class CampaignImports::AudienceDeletion
  def initialize(campaign_import)
    @campaign_import = campaign_import
  end

  def perform
    ActiveRecord::Base.transaction do
      @campaign_import.campaign_audience_links.update_all(campaign_import_id: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      CampaignImportRow.where(campaign_import_id: @campaign_import.id).delete_all
      CampaignImportLabel.where(campaign_import_id: @campaign_import.id).delete_all
      @campaign_import.destroy!
    end
  end
end
