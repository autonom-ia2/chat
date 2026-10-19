class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create]
  before_action :check_authorization
  before_action :authorize_send, only: [:create, :update]

  def index
    @campaigns = Current.account.campaigns
  end

  def show; end

  def create
    @campaign = Current.account.campaigns.create!(campaign_params)
  end

  def update
    @campaign.update!(campaign_params)
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  private

  # A one-off campaign (SMS, WhatsApp) goes out by itself at scheduled_at, which the model fills with now when it is
  # blank: creating one, or changing when it goes, needs campaign_send (#1898). Ongoing ones (site) stay with manage.
  def authorize_send
    authorize(Campaign, :send_campaign?) if sends_campaign?
  end

  def sends_campaign?
    return params[:campaign]&.key?(:scheduled_at) if action_name == 'update'

    Current.account.campaigns.new(campaign_params).tap(&:valid?).one_off?
  end

  def campaign
    @campaign ||= Current.account.campaigns.find_by(display_id: params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id,
                                     :scheduled_at, audience: [:type, :id], trigger_rules: {}, template_params: {})
  end
end
