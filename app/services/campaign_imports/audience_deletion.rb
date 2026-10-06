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
      remove_draft_email_recipients
      @campaign_import.campaign_audience_links.update_all(campaign_import_id: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      CampaignImportRow.where(campaign_import_id: @campaign_import.id).delete_all
      CampaignImportLabel.where(campaign_import_id: @campaign_import.id).delete_all
      @campaign_import.destroy!
    end
  end

  private

  # #999 review B9: e-mail drafts that used the audience lose the list it gave them (pending, never
  # sent, without events); a sent or scheduled campaign keeps its recipients and results.
  def remove_draft_email_recipients
    draft_ids = EmailCampaign.draft.where(id: @campaign_import.campaign_audience_links.where(campaign_type: 'EmailCampaign').select(:campaign_id))
                             .pluck(:id)
    return if draft_ids.empty?

    recipients = EmailCampaignRecipient.where(email_campaign_id: draft_ids)
    recipients.pending.where(sent_at: nil).where.not(id: EmailEvent.where(recipient_id: recipients.select(:id)).select(:recipient_id)).delete_all
    EmailCampaign.where(id: draft_ids).find_each(&:refresh_counters!)
  end
end
