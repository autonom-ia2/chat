class EmailCampaigns::Presentation::Hygiene
  def initialize(campaign, actor: nil, batch: nil)
    @campaign = campaign
    @actor = actor
    @batch = batch
  end

  def call
    counts = unsent_counts
    historical_sent = @batch ? @batch.historical_sent(@campaign) : @campaign.email_campaign_recipients.where.not(sent_at: nil).count
    config = EmailCampaigns::Presentation::Configuration.hygiene
    {
      mode: config.mode, status: status(counts), counts: counts,
      counts_basis: 'current_unsent_recipients', historical_sent: historical_sent, recipients_total: counts[:total] + historical_sent,
      issues_count: @batch ? @batch.issues_count(@campaign) : @campaign.email_campaign_import_issues.count,
      issues_basis: 'original_import_rows_all_imports_may_overlap_recipients',
      validation_coverage: { fresh_valid: counts[:ready], denominator: counts[:total], basis: 'current_unsent_recipients' },
      can_recheck: can_recheck?, analysis_only: !config.enforce?
    }
  end

  private

  def unsent_counts
    state = EmailCampaigns::Reports::RecipientState.new(@campaign)
    grouped = if @batch
                @batch.unsent_counts(@campaign)
              else
                @campaign.email_campaign_recipients.where(sent_at: nil).group(state.unsent_classification).count
              end
    counts = %i[ready protected invalid review unknown unchecked].index_with(0)
    grouped.each do |key, count|
      counts[key.to_sym] = count
    end
    counts.merge(total: counts.values.sum)
  end

  def status(counts) # rubocop:disable Metrics/CyclomaticComplexity -- ordered persisted progress and six exclusive recipient categories
    return 'analysing' if @campaign.preflight_summary['rechecking'] || @campaign.preflight_lease_expires_at&.future?
    return 'no_data' if counts[:total].zero?
    return 'analysing' if counts[:unchecked].positive?
    return 'review' if counts.values_at(:invalid, :review, :unknown).sum.positive?
    return 'blocked' if counts[:protected].positive?

    'ready'
  end

  def can_recheck?
    return false unless @actor
    return false if @campaign.terminal?
    return false if @batch ? @batch.import_active?(@campaign) : @campaign.recipient_import_active?

    account = @batch ? @batch.account : @campaign.account
    membership = @batch ? @batch.membership : account.account_users.find_by(user_id: @actor.id)
    EmailCampaignPolicy.new({ user: @actor, account: account, account_user: membership }, @campaign).recheck? == true
  end
end
