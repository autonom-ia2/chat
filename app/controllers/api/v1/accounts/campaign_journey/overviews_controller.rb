# Gestão de campanhas — multichannel overview (#1007, PRD D18, §6.10, O3). Read-only, account-scoped,
# campaign_view. GET …/campaign_journey/overview?days=7|30|90&channel=&page=
# Contract and the meaning of each number: docs/campaigns/publicos/resultado-1007.md.
class Api::V1::Accounts::CampaignJourney::OverviewsController < Api::V1::Accounts::BaseController
  def show
    unless ::CampaignJourney::Config.enabled?
      return render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
    end

    authorize(Campaign, :index?)
    render json: {
      payload: ::CampaignJourney::CampaignOverview.new(
        account: Current.account, days: params[:days], channel: params[:channel], page: params[:page]
      ).call
    }
  end
end
