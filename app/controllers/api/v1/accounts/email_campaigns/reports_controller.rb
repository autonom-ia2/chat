class Api::V1::Accounts::EmailCampaigns::ReportsController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :authorize_reports
  before_action :validate_hygiene_configuration
  before_action :fetch_campaign, only: [:clicks, :timeline, :recipients, :export, :import_issues, :export_import_issues]

  def index
    @summary = builder.summary
    @campaigns = builder.campaigns
    @campaign_options = builder.campaign_options
    @applied_filters = builder.applied_filters
    @preflight = builder.preflight
    @protection = builder.protection
    @meta = builder.meta
  end

  def show
    @detail = builder.campaign_detail(params[:id])
    render json: { error: 'email_campaign.not_found' }, status: :not_found if @detail.nil?
  end

  def clicks
    @clicks = builder.clicks_by_url(@campaign)
  end

  def timeline
    @timeline = builder.timeline(@campaign, interval: params[:interval])
  end

  def recipients
    query = EmailCampaigns::RecipientQuery.new(@campaign, recipient_params)
    @meta = query.meta.merge(delivery_mode: @campaign.delivery_mode)
    @recipients = EmailCampaigns::Presentation::Recipients.new(@campaign, query.paginated).call
  end

  def export
    query = EmailCampaigns::RecipientQuery.new(@campaign, recipient_params)
    csv = EmailCampaigns::Reports::CsvExport.new(scope: -> { query.call }, columns: EmailCampaigns::Reports::CsvExport::RECIPIENT_COLUMNS) do |batch|
      EmailCampaigns::Presentation::Recipients.new(@campaign, batch).call
    end
    stream_csv(csv, 'recipients')
  end

  def import_issues
    query = EmailCampaigns::Reports::ImportIssuesQuery.new(@campaign, issue_params)
    @meta = query.meta
    @issues = EmailCampaigns::Reports::ImportIssuesQuery.present(query.paginated)
    @import_summary = EmailCampaigns::Presentation::ImportSummary.new(@campaign).call
    @preflight = EmailCampaigns::Presentation::Hygiene.new(@campaign, actor: Current.user).call
  end

  def export_import_issues
    query = EmailCampaigns::Reports::ImportIssuesQuery.new(@campaign, issue_params)
    csv = EmailCampaigns::Reports::CsvExport.new(scope: query.call, columns: EmailCampaigns::Reports::CsvExport::ISSUE_COLUMNS) do |batch|
      EmailCampaigns::Reports::ImportIssuesQuery.present(batch)
    end
    stream_csv(csv, 'import_issues')
  end

  private

  def authorize_reports
    action = %w[export export_import_issues].include?(action_name) ? :export? : :view?
    authorize EmailCampaign, action, policy_class: EmailCampaignReportPolicy
  end

  def fetch_campaign
    @campaign = EmailCampaign.where(account_id: Current.account.id).find_by(id: params[:id])
    render json: { error: 'email_campaign.not_found' }, status: :not_found if @campaign.nil?
  end

  def stream_csv(csv, suffix)
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    response.headers['Content-Disposition'] = "attachment; filename=\"email_campaign_#{@campaign.id}_#{suffix}.csv\""
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Accel-Buffering'] = 'no'
    self.response_body = csv.each
  end

  def builder
    @builder ||= EmailCampaigns::Reports::Builder.new(
      account: Current.account, actor: Current.user, params: report_filter_params(%w[campaign_id status campaign_status q since until])
    )
  end

  def recipient_params
    report_filter_params(%w[q status problem page])
  end

  def issue_params
    report_filter_params(%w[q reason reason_code page])
  end
end
