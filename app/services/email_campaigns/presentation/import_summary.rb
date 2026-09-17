class EmailCampaigns::Presentation::ImportSummary
  RESULT_KEYS = %w[imported duplicates invalid suppressed total].freeze

  def initialize(campaign)
    @campaign = campaign
  end

  def call
    latest = @campaign.email_campaign_imports.order(created_at: :desc, id: :desc).first
    return unless latest

    # Do not forward arbitrary import result JSON, metadata or storage attributes.
    { id: latest.id, status: latest.status, completed_at: latest.completed_at,
      error_code: EmailCampaigns::Presentation::Errors.import_code(latest.error_code),
      result: latest.result.slice(*RESULT_KEYS),
      preflight: latest.result.fetch('preflight', {}).slice('status', 'unchecked', 'issues'),
      reasons: latest.email_campaign_import_issues.group(:reason_code).count,
      denominator: latest.result['total'], basis: 'original_rows_latest_import' }
  end

  def campaign_status
    latest = @campaign.latest_recipient_import
    return unless latest

    result = latest.result.slice(*RESULT_KEYS)
    result['preflight'] = latest.result['preflight'].slice('status', 'unchecked', 'issues') if latest.result['preflight'].is_a?(Hash)
    { id: latest.id, status: latest.status, result: result,
      error_code: EmailCampaigns::Presentation::Errors.import_code(latest.error_code), retryable: latest.retryable? }
  end
end
