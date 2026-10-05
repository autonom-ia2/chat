# Públicos (#1005): campaigns that still depend on an audience. While a linked campaign has not
# finished sending (scheduled or running), the audience cannot be deleted and the channel that
# campaign sends through cannot be turned off — both would change who receives it.
class CampaignImports::AudienceUsage
  # Engine of each linked campaign type → audience channel it reads.
  CHANNEL_BY_CAMPAIGN_TYPE = { 'Campaign' => 'whatsapp' }.freeze

  def initialize(campaign_import)
    @campaign_import = campaign_import
  end

  # A campaign type without a completed? notion counts as pending (safe side).
  def pending_campaigns(channel: nil)
    links = @campaign_import.campaign_audience_links.includes(:campaign)
    links = links.where(campaign_type: CHANNEL_BY_CAMPAIGN_TYPE.select { |_type, name| name == channel }.keys) if channel
    links.filter_map(&:campaign).reject { |campaign| campaign.respond_to?(:completed?) && campaign.completed? }
  end

  def self.error_payload(campaigns)
    {
      error: 'campaign_import.audience_in_use', code: 'audience_in_use',
      campaigns: campaigns.map { |campaign| { title: campaign.title, display_id: campaign.try(:display_id) } }
    }
  end
end
