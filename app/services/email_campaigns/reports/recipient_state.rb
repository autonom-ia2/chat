# Shared read-only SQL predicates for filtering and the hygiene presentation.
class EmailCampaigns::Reports::RecipientState
  def initialize(campaign, now: Time.current)
    @campaign = campaign
    @now = now
  end

  def protected_ids
    suppression_matches
      .or(@campaign.email_campaign_recipients.where(status: %i[suppressed unsubscribed complained]))
      .select(:id)
  end

  def opted_out_ids
    suppression_matches(reason: 'unsubscribe')
      .or(@campaign.email_campaign_recipients.where(status: :unsubscribed)).select(:id)
  end

  def preflight(status)
    @campaign.email_campaign_recipients.pending.where(sent_at: nil, preflight_status: status).where.not(id: protected_ids)
  end

  def attention
    rows = @campaign.email_campaign_recipients
    unresolved = rows.pending.where(sent_at: nil).where.not(id: ready_ids)
    rows.where(status: %i[bounced failed complained suppressed]).or(unresolved)
        .or(rows.where(id: protected_ids)).where.not(id: opted_out_ids)
  end

  def ready_ids
    @campaign.email_campaign_recipients.pending.where(sent_at: nil, preflight_status: 'valid')
             .where.not(preflight_checked_at: nil).where('preflight_valid_until > ?', @now).select(:id)
  end

  def resume_candidates
    @campaign.email_campaign_recipients.pending.where(sent_at: nil, ses_message_id: [nil, '']).where.not(id: protected_ids)
  end

  def unsent_classification
    Arel.sql(<<~SQL.squish)
      CASE WHEN id IN (#{protected_ids.to_sql}) THEN 'protected'
           WHEN status != #{EmailCampaignRecipient.statuses.fetch('pending')} THEN 'unknown'
           WHEN id IN (#{ready_ids.to_sql}) THEN 'ready'
           WHEN preflight_status IN ('invalid', 'review', 'unknown') THEN preflight_status
           ELSE 'unchecked' END
    SQL
  end

  private

  # Legacy rows are permanent positives. Match the batch API's legacy-first reason
  # precedence in SQL, without loading an account's entire suppression list.
  def suppression_matches(reason: nil)
    legacy = EmailSuppression.where(account_id: @campaign.account_id).select('lower(email)')
    states = EmailSuppressionState.blocking.where(account_id: @campaign.account_id).select('lower(email)')
    if reason
      states = states.where(reason: reason).where("lower(email) NOT IN (#{legacy.to_sql})")
      legacy = legacy.where(reason: reason)
    end
    @campaign.email_campaign_recipients.where("lower(email) IN (#{legacy.to_sql} UNION #{states.to_sql})")
  end
end
