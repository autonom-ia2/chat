# Result of one campaign (#1007, PRD §6.5, O1–O2, E1–E4). Read-only, account-scoped.
# Contract: docs/campaigns/publicos/resultado-1007.md.
#
#   GET …/campaign_journey/results/:channel/:id             campaign, totals and the CRM mark
#   GET …/campaign_journey/results/:channel/:id/recipients  people, 25 per page, ?status=
#   GET …/campaign_journey/results/:channel/:id/export      masked CSV, ?status=
#
# channel: email | whatsapp_official | whatsapp_api | sms. campaign_view reads; the export needs
# campaign_manage, like the e-mail reports export. CAMPAIGN_JOURNEY_ENABLED off → 404.
class Api::V1::Accounts::CampaignJourney::ResultsController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_journey_enabled
  before_action :authorize_result
  before_action :fetch_result
  before_action :validate_status_filter, only: [:recipients, :export]

  def show
    render json: {
      payload: {
        campaign: @result.campaign_payload,
        totals: @result.totals,
        filters: @result.filters,
        crm: { source_id: @result.source_id, enabled: Crm::Config.enabled? }
      }
    }
  end

  def recipients
    render json: { payload: @result.page(filter: status_filter, page: page_param, visible_conversations: visible_conversations) }
  end

  def export
    export = ::CampaignJourney::ResultExport.new(@result, filter: status_filter)
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    response.headers['Content-Disposition'] = "attachment; filename=\"#{export.filename}\""
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Accel-Buffering'] = 'no'
    self.response_body = export.csv.each
  end

  private

  def authorize_result
    authorize(Campaign, action_name == 'export' ? :create? : :show?)
  end

  def fetch_result
    @result = ::CampaignJourney::ResultFinder.new(Current.account).find!(params[:channel].to_s, params[:id])
  end

  def status_filter
    params[:status].presence&.to_s
  end

  def validate_status_filter
    return if status_filter.nil? || @result.filters.include?(status_filter)

    render json: { error: 'campaign_journey.invalid_filter', parameter: 'status' }, status: :unprocessable_entity
  end

  def page_param
    [params[:page].to_i, 1].max
  end

  # Same visibility the conversation list uses: "Abrir conversa" only for conversations the agent can open.
  def visible_conversations
    Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform.reorder(nil)
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end
end
