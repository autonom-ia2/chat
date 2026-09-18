class EmailCampaigns::Reports::ImportIssuesQuery
  CLASSIFICATIONS = { 'duplicate' => 'duplicate', 'suppressed' => 'protected',
                      'invalid_email' => 'invalid', 'blank_email' => 'invalid', 'invalid_recipient' => 'review' }.freeze
  attr_reader :page, :applied_filters

  def initialize(campaign, params = {})
    @campaign = campaign
    input = EmailCampaigns::Reports::Parameters.new(params, allowed: %w[q reason reason_code page])
    @page = input.page
    reason = input.text(:reason, max: 100)
    reason_code = input.text(:reason_code, max: 100)
    raise EmailCampaigns::Reports::Parameters::Invalid, 'reason_code' if reason && reason_code && reason != reason_code

    @applied_filters = { q: input.text(:q), reason: reason || reason_code }.compact
    return unless applied_filters[:reason] && !applied_filters[:reason].match?(/\A[a-z][a-z0-9_]*\z/)

    raise EmailCampaigns::Reports::Parameters::Invalid, 'reason'
  end

  def call
    rows = @campaign.email_campaign_import_issues
    rows = rows.where(reason_code: applied_filters[:reason]) if applied_filters[:reason]
    rows = rows.where('raw_address ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(applied_filters[:q])}%") if applied_filters[:q]
    rows.order(:id)
  end

  def paginated
    call.offset((page - 1) * EmailCampaigns::Reports::Parameters::PER_PAGE).limit(EmailCampaigns::Reports::Parameters::PER_PAGE)
  end

  def meta
    EmailCampaigns::Reports::Parameters.meta(call.count, page, applied_filters)
  end

  def self.present(rows)
    rows.map do |issue|
      { id: issue.id, row_number: issue.row_number, raw_email: issue.raw_address, email: issue.raw_address,
        reason_code: issue.reason_code, suggestion: issue.suggestion, classification: CLASSIFICATIONS.fetch(issue.reason_code, 'unknown') }
    end
  end
end
