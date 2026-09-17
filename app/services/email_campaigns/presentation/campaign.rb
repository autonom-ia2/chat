# One request-local account presenter for a whole list. Never collects reputation.
class EmailCampaigns::Presentation::Campaign
  def initialize(account:, actor:, campaigns: nil)
    @batch = EmailCampaigns::Presentation::CampaignBatch.new(account: account, actor: actor, campaigns: campaigns) if campaigns
    @protection = EmailCampaigns::Presentation::Protection.new(account: account, actor: actor, batch: @batch)
    @actor = actor
  end

  def call(campaign)
    preflight = EmailCampaigns::Presentation::Hygiene.new(campaign, actor: @actor, batch: @batch).call
    { preflight: preflight, protection: @protection.call(campaign: campaign, preflight: preflight) }
  end
end
