# Resumes a paused campaign (#1329). Backend only for now; the Resultado button comes later (#1320 D).
#
#   POST …/campaign_journey/campaign_pauses/:id/resume
#
# campaign_manage required (CampaignPolicy#update?). The pause must belong to the account. A Chatwoot
# one-off campaign still `active` is fired again right away and its template is checked again
# (CampaignPauses::Resumer). 422 with `code`: pause_not_open | campaign_already_sent.
# CAMPAIGN_JOURNEY_ENABLED off → 404.
class Api::V1::Accounts::CampaignJourney::CampaignPausesController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_journey_enabled
  before_action :authorize_resume
  before_action :fetch_pause

  def resume
    pause = ::CampaignPauses::Resumer.new(@pause, resumed_by: Current.user).perform
    render json: { payload: pause.payload }
  rescue ::CampaignPauses::Resumer::Error => e
    render json: { error: 'campaign_journey.pause_not_resumable', code: e.code }, status: :unprocessable_entity
  end

  private

  def authorize_resume
    authorize(Campaign, :update?)
  end

  def fetch_pause
    @pause = CampaignPause.where(account_id: Current.account.id).find(params[:id])
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end
end
