# #1005 M2: a WhatsApp Oficial campaign linked to an audience that stays `processing` with no
# recipient moving for STALL_AFTER (worker killed, deploy in the middle of a send) is closed:
# every still-queued recipient becomes failed with REASON and the campaign is completed, so the
# result never keeps people without a status. Registered in config/schedule.yml.
class CampaignJourney::StalledCampaignsJob < ApplicationJob
  queue_as :scheduled_jobs

  STALL_AFTER = 2.hours
  REASON = 'envio interrompido'.freeze

  def perform
    linked = CampaignAudienceLink.where(campaign_type: 'Campaign').select(:campaign_id)
    Campaign.processing.where(id: linked).where(started_at: ...STALL_AFTER.ago).find_each do |campaign|
      close(campaign) if stalled?(campaign)
    end
  end

  private

  def stalled?(campaign)
    last_move = campaign.campaign_recipients.maximum(:updated_at)
    last_move.nil? || last_move < STALL_AFTER.ago
  end

  def close(campaign)
    campaign.with_lock do
      next unless campaign.processing?

      campaign.campaign_recipients.queued.find_each { |recipient| recipient.mark_failed!(message: REASON) }
      campaign.completed!
    end
    Rails.logger.warn "[CampaignJourney] stalled campaign #{campaign.id} closed"
  end
end
