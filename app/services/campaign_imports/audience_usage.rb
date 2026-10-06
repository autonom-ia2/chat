# Públicos (#1005): campaigns that still depend on an audience. While a linked campaign has not
# finished sending (scheduled or running), the audience cannot be deleted and the channel that
# campaign sends through cannot be turned off — both would change who receives it.
# A campaign still `active` but scheduled more than SCHEDULER_WINDOW ago is not pending: the
# scheduler (TriggerScheduledItemsJob) only picks campaigns scheduled in the last 3 days, so it
# will never send. `processing` campaigns stay pending until they finish (or
# CampaignJourney::StalledCampaignsJob closes them).
class CampaignImports::AudienceUsage
  # Engine of each linked campaign type → audience channel it reads. A Chatwoot Campaign on an SMS
  # inbox reads the sms badge (#1004).
  CHANNEL_BY_CAMPAIGN_TYPE = { 'Campaign' => 'whatsapp', 'WhatsappApiCampaign' => 'whatsapp', 'EmailCampaign' => 'email' }.freeze
  SCHEDULER_WINDOW = 3.days

  def initialize(campaign_import)
    @campaign_import = campaign_import
  end

  # A campaign type without a completed? notion counts as pending (safe side).
  def pending_campaigns(channel: nil)
    links = @campaign_import.campaign_audience_links.includes(:campaign)
    campaigns = links.filter_map(&:campaign).reject { |campaign| finished?(campaign) }
    channel ? campaigns.select { |campaign| channel_of(campaign) == channel } : campaigns
  end

  def channel_of(campaign)
    return 'sms' if campaign.is_a?(Campaign) && CampaignJourney::CampaignMarks.sms_inbox?(campaign.inbox)

    CHANNEL_BY_CAMPAIGN_TYPE[campaign.class.name]
  end

  def in_use?
    pending_campaigns.any?
  end

  # E-mail and WhatsApp API campaigns (#999): finished when terminal; an e-mail draft has not
  # been scheduled yet, so it does not hold the audience (its send re-checks the channel).
  def finished?(campaign)
    return campaign.terminal? || campaign.try(:draft?) == true if campaign.respond_to?(:terminal?)
    return false unless campaign.respond_to?(:completed?)
    return true if campaign.completed?

    campaign.try(:active?) && campaign.scheduled_at.present? && campaign.scheduled_at < SCHEDULER_WINDOW.ago
  end

  def self.error_payload(campaigns)
    {
      error: 'campaign_import.audience_in_use', code: 'audience_in_use',
      campaigns: campaigns.map { |campaign| { title: campaign.try(:title) || campaign.try(:name), display_id: campaign.try(:display_id) } }
    }
  end
end
