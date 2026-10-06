# "Vão receber" of a journey campaign before it exists (#993, PRD §6.4, B8): the exact number of
# people the send reaches and why the others do not, counted once (CampaignJourney::RecipientPreview).
# POST because the variable bindings travel as JSON; nothing is written.
# CAMPAIGN_JOURNEY_ENABLED off → 404; campaign_manage required (CampaignPolicy#create?), otherwise 401.
class Api::V1::Accounts::CampaignJourney::RecipientPreviewsController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_journey_enabled
  before_action :check_authorization

  def create
    # Contact imports (#1006) are never audiences: campaign_flows keeps them out.
    campaign_import = Current.account.campaign_imports.campaign_flows.find(params.require(:campaign_import_id))
    preview = ::CampaignJourney::RecipientPreview.new(
      campaign_import, channel: params[:channel], variable_bindings: hash_param(:variable_bindings),
                       variable_defaults: hash_param(:variable_defaults), message_body: params[:message_body]
    ).perform
    render json: { payload: preview }
  rescue ArgumentError => e
    render json: { error: e.message, code: e.message }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize(Campaign, :create?)
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end

  def hash_param(key)
    value = params[key]
    value.respond_to?(:permit!) ? value.permit!.to_h : {}
  end
end
