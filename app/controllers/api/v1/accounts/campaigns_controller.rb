class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create]
  before_action :check_authorization

  def index
    @campaigns = Current.account.campaigns
  end

  def show; end

  def create
    @campaign = Current.account.campaigns.create!(persisted_campaign_params)
  rescue Campaigns::ScheduledAtParser::NaiveWithoutZoneError, Campaigns::ScheduledAtParser::InvalidError => e
    render_could_not_create_error(e.message)
  end

  def update
    @campaign.update!(persisted_campaign_params)
  rescue Campaigns::ScheduledAtParser::NaiveWithoutZoneError, Campaigns::ScheduledAtParser::InvalidError => e
    render_could_not_create_error(e.message)
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by(display_id: params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id,
                                     :scheduled_at, audience: [:type, :id], trigger_rules: {}, template_params: {})
  end

  # Interpret a naive `scheduled_at` in the account/inbox operational zone
  # (via TimeZoneResolver) instead of letting AR type-cast collapse it to UTC.
  # A string with an explicit offset is honored as-is; a naive string with no
  # resolvable zone fails closed (422) rather than firing at the wrong local
  # time.
  def persisted_campaign_params
    attrs = campaign_params
    return attrs if attrs[:scheduled_at].blank?

    attrs.merge(scheduled_at: resolved_scheduled_at(attrs))
  end

  def resolved_scheduled_at(attrs)
    Campaigns::ScheduledAtParser.call(
      value: attrs[:scheduled_at],
      account: Current.account,
      inbox: scheduling_inbox(attrs)
    )
  end

  def scheduling_inbox(attrs)
    inbox_id = attrs[:inbox_id] || @campaign&.inbox_id
    return nil if inbox_id.blank?

    Current.account.inboxes.find_by(id: inbox_id)
  end
end
