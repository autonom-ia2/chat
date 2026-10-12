# Closes the open pause of a campaign (#1329) and, for a Chatwoot one-off campaign still `active`,
# fires it again right away (the scheduler only looks 3 days back, so a long pause would never be
# picked up again). The dispatch check runs again on that trigger: a template that still does not
# match opens a new pause and nobody receives anything.
#
# Never sends twice:
# - Campaign#trigger! flips active → processing under a row lock and returns for processing or
#   completed campaigns, so a completed campaign never goes out again (only `active` ones are fired here).
# - A pause opens before the first recipient is created. A campaign that already has recipients past
#   `queued` started sending; resuming it is refused (`campaign_already_sent`) and the pause stays,
#   because Enterprise's label path processes every recipient again.
class CampaignPauses::Resumer
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  def initialize(pause, resumed_by: nil)
    @pause = pause
    @resumed_by = resumed_by
  end

  # Locked: two resumes of the same pause never both pass; the second gets pause_not_open. The job is
  # enqueued after the commit, so the trigger never reads the pause still open.
  def perform
    CampaignPause.transaction do
      @pause.lock!
      campaign = @pause.pausable
      raise Error, 'pause_not_open' unless @pause.open?
      raise Error, 'campaign_already_sent' if already_sent?(campaign)

      @pause.update!(resumed_at: Time.current, resumed_by: @resumed_by)
      retrigger(campaign)
    end
    @pause
  end

  private

  def already_sent?(campaign)
    return false unless campaign.is_a?(Campaign) && defined?(CampaignRecipient)

    CampaignRecipient.where(campaign_id: campaign.id).where.not(status: 'queued').exists?
  end

  def retrigger(campaign)
    return unless campaign.is_a?(Campaign) && campaign.one_off? && campaign.active?

    ActiveRecord.after_all_transactions_commit { Campaigns::TriggerOneoffCampaignJob.perform_later(campaign) }
  end
end
