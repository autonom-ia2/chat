# Gestão de campanhas — multichannel overview (#1007, PRD D18, §6.10, O3). Read-only, account-scoped,
# campaign_view. GET …/campaign_journey/overview?days=7|30|90&channel=&page=
# Contract and the meaning of each number: docs/campaigns/publicos/resultado-1007.md.
# #3099 (D5): `duas_versoes_esperando` lists the campaigns whose test ended under "eu escolho" and wait for someone to
# pick the version (CampaignJourney::DuasVersoes::Esperando), for the warning on the campaigns list.
class Api::V1::Accounts::CampaignJourney::OverviewsController < Api::V1::Accounts::BaseController
  def show
    unless ::CampaignJourney::Config.enabled?
      return render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
    end

    authorize(Campaign, :index?)
    render json: {
      payload: ::CampaignJourney::CampaignOverview.new(
        account: Current.account, days: params[:days], channel: params[:channel], page: params[:page],
        reader: { user: Current.user, account_user: Current.account_user }
      ).call.merge(duas_versoes_esperando: ::CampaignJourney::DuasVersoes::Esperando.new(Current.account).payload)
    }
  end
end
