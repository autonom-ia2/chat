# One request-local account presenter for a whole list. Never collects reputation.
class EmailCampaigns::Presentation::Campaign
  def initialize(account:, actor:)
    @protection = EmailCampaigns::Presentation::Protection.new(account: account, actor: actor)
    @actor = actor
  end

  def call(campaign)
    preflight = EmailCampaigns::Presentation::Hygiene.new(campaign, actor: @actor).call
    { preflight: preflight, protection: @protection.call(campaign: campaign, preflight: preflight) }
  end
end
