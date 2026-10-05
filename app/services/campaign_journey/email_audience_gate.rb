# An e-mail campaign linked to an audience (#999) only goes out while the audience's e-mail
# channel is on (fails closed): the recipients were written from the audience while it was a
# draft, so turning the channel off afterwards must stop the send, not just the next draft.
# Scheduled or sending campaigns already keep the channel from being turned off
# (CampaignImports::AudienceUsage); this covers the draft that is sent or scheduled later.
# Prepended by config/initializers/campaign_journey.rb.
module CampaignJourney::EmailAudienceGate
  def self.channel_on?(campaign)
    link = CampaignAudienceLink.for_campaign(campaign)
    link.nil? || CampaignJourney::AudienceContacts.email_enabled?(link.campaign_import)
  end

  # EmailCampaign: send_now, schedule! and the scheduler all go through sendable?. Before each
  # of them (and before a scheduled campaign starts) the audience recipients are synced, up to
  # the first send (CampaignJourney::EmailAudienceRecipients#sync!).
  module Campaign
    def claim_for_sending!
      CampaignJourney::EmailAudienceRecipients.new(self).sync!
      super
    end

    def schedule!(scheduled_at:)
      CampaignJourney::EmailAudienceRecipients.new(self).sync!
      super
    end

    def mark_sending!
      CampaignJourney::EmailAudienceRecipients.new(self).sync! if scheduled?
      super
    end

    def sendable_recipients?
      super && CampaignJourney::EmailAudienceGate.channel_on?(self)
    end
  end

  # EmailCampaigns::Presentation::SendReadiness: the readiness list says why.
  module Readiness
    private

    def send_checks(eligible)
      checks = super
      return checks if CampaignJourney::EmailAudienceGate.channel_on?(@campaign)

      checks.merge(recipients: false, audience_channel: false)
    end
  end
end
