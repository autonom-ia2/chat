# Opens the pause of a campaign (#1329). Idempotent: when the campaign already has an open pause, that
# one is kept and returned (partial unique index idx_campaign_pauses_one_open). A Chatwoot Campaign
# that was flipped to `processing` by Campaign#trigger! goes back to `active` in the same transaction,
# so nothing reads it as "sending" and CampaignPauses::TriggerGate keeps it from firing again.
class CampaignPauses::Pauser
  def initialize(pausable, source:, reason_code:, details: {}, paused_by: nil)
    @pausable = pausable
    @attributes = { source: source, reason_code: reason_code, details: details, paused_by: paused_by }
  end

  def perform
    CampaignPause.transaction do
      pause = CampaignPause.open_for(@pausable) || create_pause
      back_to_active
      pause
    end
  end

  private

  # A concurrent pause of the same campaign wins the unique index; its row is the open pause.
  def create_pause
    CampaignPause.transaction(requires_new: true) do
      CampaignPause.create!(@attributes.merge(account_id: @pausable.account_id, pausable: @pausable, paused_at: Time.current))
    end
  rescue ActiveRecord::RecordNotUnique
    CampaignPause.open_for(@pausable)
  end

  # Locked and reloaded: only a campaign still `processing` (this run) goes back to `active`; a
  # campaign another run already completed is never reopened.
  def back_to_active
    return unless @pausable.is_a?(Campaign)

    @pausable.with_lock do
      @pausable.update!(campaign_status: :active) if @pausable.processing?
    end
  end
end
