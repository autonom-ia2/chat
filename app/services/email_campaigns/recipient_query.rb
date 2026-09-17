class EmailCampaigns::RecipientQuery
  ALIASES = { 'hard_bounced' => 'permanent', 'temporary_bounced' => 'temporary', 'unknown_bounced' => 'unknown' }.freeze
  PREFLIGHT = %w[preflight_invalid preflight_review preflight_unknown].freeze
  attr_reader :page, :applied_filters

  # The caller MUST obtain campaign through the current account's authorized scope.
  def initialize(campaign, params = {})
    @campaign = campaign
    input = EmailCampaigns::Reports::Parameters.new(params, allowed: %w[q status problem page])
    @page = input.page
    @applied_filters = { q: input.text(:q), status: input.choice(:status, EmailCampaignRecipient.statuses.keys + ALIASES.keys + PREFLIGHT),
                         problem: input.boolean(:problem) }.compact
  end

  def call
    build_scope
  end

  def paginated
    call.offset((page - 1) * EmailCampaigns::Reports::Parameters::PER_PAGE).limit(EmailCampaigns::Reports::Parameters::PER_PAGE)
  end

  def meta
    EmailCampaigns::Reports::Parameters.meta(call.count, page, applied_filters)
  end

  private

  def build_scope
    rows = @campaign.email_campaign_recipients
    if applied_filters[:q]
      term = "%#{ActiveRecord::Base.sanitize_sql_like(applied_filters[:q])}%"
      rows = rows.where('email ILIKE :term OR name ILIKE :term', term: term)
    end
    rows = filter_status(rows, applied_filters[:status]) if applied_filters[:status]
    unless applied_filters[:problem].nil?
      attention = EmailCampaigns::Reports::RecipientState.new(@campaign).attention.select(:id)
      rows = applied_filters[:problem] ? rows.where(id: attention) : rows.where.not(id: attention)
    end
    rows.order(:id)
  end

  def filter_status(rows, status)
    if ALIASES.key?(status)
      EmailCampaigns::Reports::BounceOutcomes.new(rows.bounced).matching(ALIASES.fetch(status))
    elsif PREFLIGHT.include?(status)
      rows.where(id: EmailCampaigns::Reports::RecipientState.new(@campaign).preflight(status.delete_prefix('preflight_')).select(:id))
    else
      rows.where(status: status)
    end
  end
end
