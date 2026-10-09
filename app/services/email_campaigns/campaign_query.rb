class EmailCampaigns::CampaignQuery
  ATTENTION_STATUSES = %w[paused failed].freeze
  attr_reader :applied_filters

  def initialize(account:, params: {})
    @account = account
    input = EmailCampaigns::Reports::Parameters.new(params, allowed: %w[q status campaign_status campaign_id since until])
    status = input.choice(:status, EmailCampaign.statuses.keys + ['attention'])
    campaign_status = input.choice(:campaign_status, EmailCampaign.statuses.keys + ['attention'])
    raise EmailCampaigns::Reports::Parameters::Invalid, 'campaign_status' if status && campaign_status && status != campaign_status

    # Legacy clients may omit these values; nonempty dates have never been applied.
    %i[since until].each { |key| raise EmailCampaigns::Reports::Parameters::Invalid, key if input.text(key) }
    @applied_filters = { q: input.text(:q), campaign_status: campaign_status || status,
                         campaign_id: input.positive_integer(:campaign_id) }.compact
  end

  def call
    rows = options
    rows = rows.where(id: applied_filters[:campaign_id]) if applied_filters[:campaign_id]
    status = applied_filters[:campaign_status]
    rows = rows.where(status: status == 'attention' ? ATTENTION_STATUSES : status) if status
    if applied_filters[:q]
      term = "%#{ActiveRecord::Base.sanitize_sql_like(applied_filters[:q])}%"
      rows = rows.where('name ILIKE :term OR subject ILIKE :term', term: term)
    end
    rows
  end

  # All authorized account campaigns, independent of every selection filter.
  def options
    EmailCampaignPolicy::Scope.new({ account: @account }, EmailCampaign).resolve.order(created_at: :desc, id: :desc)
  end
end
