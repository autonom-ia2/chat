# Campaign label of a message sent by a campaign (#1002, PRD D20, §6.11 and P2). Messages keep
# only the campaign id (additional_attributes.campaign_id / whatsapp_api_campaign_id); the
# conversation bubble asks here for the names. Read-only, account-scoped.
class Api::V1::Accounts::CampaignJourney::CampaignNamesController < Api::V1::Accounts::BaseController
  MAX_IDS = 100

  def index
    authorize ::Conversation, :index?

    render json: {
      payload: {
        campaigns: Current.account.campaigns.where(id: ids_param(params[:campaign_ids])).pluck(:id, :title).to_h,
        whatsapp_api_campaigns: WhatsappApiCampaign.where(account_id: Current.account.id, id: ids_param(params[:whatsapp_api_campaign_ids]))
                                                   .pluck(:id, :title).to_h
      }
    }
  end

  private

  def ids_param(value)
    value.to_s.split(',').filter_map { |id| Integer(id, exception: false) }.first(MAX_IDS)
  end
end
