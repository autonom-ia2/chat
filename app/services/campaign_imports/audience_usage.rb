# Públicos (#1005): campaigns that still depend on an audience. While a linked campaign has not
# finished sending (scheduled or running), the audience cannot be deleted and the channel that
# campaign sends through cannot be turned off — both would change who receives it.
# A campaign still `active` but scheduled more than SCHEDULER_WINDOW ago is not pending: the
# scheduler (TriggerScheduledItemsJob) only picks campaigns scheduled in the last 3 days, so it
# will never send. `processing` campaigns stay pending until they finish (or
# CampaignJourney::StalledCampaignsJob closes them).
class CampaignImports::AudienceUsage
  # Engine of each linked campaign type → audience channel it reads.
  CHANNEL_BY_CAMPAIGN_TYPE = { 'Campaign' => 'whatsapp' }.freeze
  SCHEDULER_WINDOW = 3.days

  def initialize(campaign_import)
    @campaign_import = campaign_import
  end

  # A campaign type without a completed? notion counts as pending (safe side).
  def pending_campaigns(channel: nil)
    links = @campaign_import.campaign_audience_links.includes(:campaign)
    links = links.where(campaign_type: CHANNEL_BY_CAMPAIGN_TYPE.select { |_type, name| name == channel }.keys) if channel
    links.filter_map(&:campaign).reject { |campaign| finished?(campaign) }
  end

  def in_use?
    pending_campaigns.any?
  end

  def finished?(campaign)
    return false unless campaign.respond_to?(:completed?)
    return true if campaign.completed?

    campaign.try(:active?) && campaign.scheduled_at.present? && campaign.scheduled_at < SCHEDULER_WINDOW.ago
  end

  def self.error_payload(campaigns)
    {
      error: 'campaign_import.audience_in_use', code: 'audience_in_use',
      campaigns: campaigns.map { |campaign| { title: campaign.title, display_id: campaign.try(:display_id) } }
    }
  end
end
