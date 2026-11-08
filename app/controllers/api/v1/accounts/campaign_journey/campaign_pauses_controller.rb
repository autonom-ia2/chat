# Paused campaigns (#1329) and how to resume them.
#
#   GET  …/campaign_journey/campaign_pauses              open pauses of the account's campaigns (#1332)
#   POST …/campaign_journey/campaign_pauses/:id/resume   resume one pause
#
# index: campaign_view (CampaignPolicy#index?). Lists only open pauses of Chatwoot campaigns (WhatsApp
# Oficial today), newest first, with the campaign, the reason and `ready_to_resume` (the template is approved again
# and matches what the campaign recorded, read from the freshest cached list of the same WhatsApp account —
# CampaignPauses::ResumeReadiness) — the Modelos screen and the campaign list show
# them with "Retomar". details never carry personal data (CampaignPause).
# resume: campaign_send (CampaignPolicy#send_campaign?, #1898). The pause must belong to the account. A Chatwoot
# one-off campaign still `active` is fired again right away and its template is checked again
# (CampaignPauses::Resumer). 422 with `code`: pause_not_open | campaign_already_sent.
# CAMPAIGN_JOURNEY_ENABLED off → 404.
class Api::V1::Accounts::CampaignJourney::CampaignPausesController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 100

  before_action :ensure_campaign_journey_enabled
  before_action :authorize_index, only: :index
  before_action :authorize_resume, only: :resume
  before_action :fetch_pause, only: :resume

  def index
    pauses = CampaignPause.in_effect.where(account_id: Current.account.id, pausable_type: 'Campaign')
                          .includes(pausable: { inbox: :channel }).order(paused_at: :desc).limit(LIST_LIMIT)
    readiness = ::CampaignPauses::ResumeReadiness.new(Current.account)
    render json: { payload: pauses.filter_map { |pause| list_item(pause, readiness) } }
  end

  def resume
    pause = ::CampaignPauses::Resumer.new(@pause, resumed_by: Current.user).perform
    render json: { payload: pause.payload }
  rescue ::CampaignPauses::Resumer::Error => e
    render json: { error: 'campaign_journey.pause_not_resumable', code: e.code }, status: :unprocessable_entity
  end

  private

  def list_item(pause, readiness)
    campaign = pause.pausable
    return unless campaign

    pause.payload.merge(
      campaign: { id: campaign.id, display_id: campaign.display_id, title: campaign.title, inbox_id: campaign.inbox_id,
                  scheduled_at: campaign.scheduled_at },
      ready_to_resume: readiness.ready?(campaign)
    )
  end

  def authorize_index
    authorize(Campaign, :index?)
  end

  def authorize_resume
    authorize(Campaign, :send_campaign?)
  end

  def fetch_pause
    @pause = CampaignPause.where(account_id: Current.account.id).find(params[:id])
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end
end
