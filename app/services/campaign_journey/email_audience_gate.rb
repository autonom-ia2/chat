# An e-mail campaign linked to an audience (#999) only goes out while the audience's e-mail
# channel is on (fails closed), and its list follows the audience until the first send.
# Prepended by config/initializers/campaign_journey.rb.
#
# Lock order (review M3): the audience row first, then the delivery locks (account → reputation
# state → provider → campaign). The channel switch and the audience delete lock only the
# audience row, so they never wait in the opposite order. The sync and the channel check run
# inside the delivery locks, before the engine's sendable? check (review M1).
module CampaignJourney::EmailAudienceGate
  def self.channel_on?(campaign)
    link = CampaignAudienceLink.for_campaign(campaign)
    link.nil? || CampaignJourney::AudienceContacts.email_enabled?(link.campaign_import)
  end

  # Yields inside audience lock + delivery locks; a campaign without an audience just yields.
  def self.with_audience_locks(campaign, &)
    link = CampaignAudienceLink.for_campaign(campaign)
    return yield unless link&.campaign_import

    ActiveRecord::Base.transaction do
      link.campaign_import.lock!
      campaign.with_delivery_lock(&)
    end
  end

  def self.sync!(campaign)
    CampaignJourney::EmailAudienceRecipients.new(campaign).sync!
  end

  # EmailCampaign: send_now (claim_for_sending!) and schedule! sync the list first.
  module Campaign
    def claim_for_sending!
      CampaignJourney::EmailAudienceGate.with_audience_locks(self) do
        CampaignJourney::EmailAudienceGate.sync!(self)
        super
      end
    end

    def schedule!(scheduled_at:)
      CampaignJourney::EmailAudienceGate.with_audience_locks(self) do
        CampaignJourney::EmailAudienceGate.sync!(self)
        super
      end
    end

    def sendable_recipients?
      super && CampaignJourney::EmailAudienceGate.channel_on?(self)
    end
  end

  # EmailCampaigns::Scheduler (review M2): a due linked campaign syncs its list before the
  # hygiene/admission checks. When the list grew, the new addresses get the hygiene preflight
  # and the send waits for the next tick instead of pausing the campaign; in enforce mode it
  # keeps waiting while synced addresses are still unchecked.
  module Scheduler
    private

    def start(campaign)
      return super unless CampaignAudienceLink.for_campaign(campaign)
      return if wait_for_audience_list?(campaign)

      super
    end

    def wait_for_audience_list?(campaign)
      added = CampaignJourney::EmailAudienceGate.with_audience_locks(campaign) do
        campaign.reload
        campaign.scheduled? ? CampaignJourney::EmailAudienceGate.sync!(campaign)[:added] : 0
      end
      return true if added.positive?

      awaiting_hygiene?(campaign)
    rescue StandardError => e
      Rails.logger.error("[CampaignJourney::EmailAudienceGate] campaign=#{campaign.id} #{e.class.name}: " \
                         "#{EmailCampaigns::SafeErrorMessage.call(e.message)}")
      true
    end

    def awaiting_hygiene?(campaign)
      return false unless EmailCampaigns::HygieneConfig.new.enforce?

      unchecked = campaign.email_campaign_recipients.pending.where.not(contact_id: nil).exists?(preflight_status: 'unchecked')
      EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id) if unchecked
      unchecked
    end
  end

  # EmailCampaigns::Presentation::SendReadiness: the readiness list says why, and how the list
  # will change when the campaign is scheduled or sent (audience_list: { to_add:, to_remove: }).
  module Readiness
    def call
      result = super
      return result unless CampaignAudienceLink.for_campaign(@campaign)

      result.merge(audience_list: CampaignJourney::EmailAudienceRecipients.new(@campaign).preview)
    end

    private

    def send_checks(eligible)
      checks = super
      return checks if CampaignJourney::EmailAudienceGate.channel_on?(@campaign)

      checks.merge(recipients: false, audience_channel: false)
    end
  end
end
