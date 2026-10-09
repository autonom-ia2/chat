module EmailCampaigns
  # Picks up due scheduled campaigns, transitions them to sending under a lock, and enqueues
  # delivery. Guarded by Config.enabled?; defensive per-campaign so one failure never strands
  # the batch.
  class Scheduler
    def perform
      return unless Config.enabled?

      EmailCampaign.due.find_each(batch_size: 50) { |campaign| start(campaign) }
    end

    private

    def ready?(campaign)
      campaign.scheduled? && campaign.scheduled_at <= Time.current && campaign.sender_ready? && !campaign.recipient_import_active?
    end

    def start(campaign)
      enqueue = campaign.with_lock do
        campaign.reload
        next unless ready?(campaign)

        unless EmailCampaigns::PreflightDecision.new.campaign_allowed?(campaign)
          EmailCampaigns::PreflightDecision.new.pause!(campaign)
          next
        end

        campaign.mark_sending!
        true
      end
      EmailCampaigns::DeliveryJob.perform_later(campaign.id) if enqueue && Config.enabled?
    rescue StandardError => e
      campaign&.update(status: :failed, last_error: e.message.to_s.truncate(500))
    end
  end
end
