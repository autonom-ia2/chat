class EmailCampaigns::Maintenance::Evidence
  STRONG_REASONS = %w[provider_suppression hard_bounce complaint unsubscribe manual].freeze
  attr_reader :email, :campaign, :reason, :event_key, :occurred_at, :metadata, :skip

  def self.events(account_id)
    EmailEvent.joins(recipient: :email_campaign).where(email_campaigns: { account_id: account_id })
  end

  def initialize(row, account_id:)
    @metadata = {}
    if row.is_a?(EmailEvent)
      from_event(row, account_id)
    else
      from_legacy(row, account_id)
    end
  end

  private

  def from_event(row, account_id)
    @campaign = row.recipient.email_campaign
    raise ArgumentError, 'account_mismatch' unless @campaign.account_id == account_id

    @email = row.recipient.email
    @occurred_at = row.occurred_at
    @metadata = { 'historical_event_id' => row.id }
    @reason = case row.event_type
              when 'unsubscribe' then 'unsubscribe'
              when 'complaint' then complaint_reason(row.payload)
              when 'bounce' then bounce_reason(row.payload)
              else
                @skip = 'skipped_other_events'
                nil
              end
    @event_key = event_key_for(row) if @reason
  end

  def complaint_reason(payload)
    complaint = payload.is_a?(Hash) && payload['complaint'].is_a?(Hash) ? payload['complaint'] : {}
    prevented = EmailCampaigns::ComplaintClassifier.provider_prevented?(complaint)
    @metadata['reason_code'] = prevented ? 'provider_suppression' : 'complaint'
    prevented ? 'provider_suppression' : 'complaint'
  end

  def bounce_reason(payload)
    bounce = payload.is_a?(Hash) && payload['bounce'].is_a?(Hash) ? payload['bounce'] : {}
    result = EmailCampaigns::BounceClassifier.call(bounce)
    @metadata.merge!(result)
    return result['reason_code'] if %w[provider_suppression unsubscribe].include?(result['reason_code'])
    return 'hard_bounce' if result.fetch('classification') == 'permanent'

    @skip = result['classification'] == 'temporary' ? 'skipped_temporary_events' : 'skipped_unknown_events'
    nil
  end

  def event_key_for(row)
    return "unsubscribe:#{row.recipient_id}" if row.unsubscribe?

    # Match live SNS keys; a historical event without an SNS id uses its durable row id.
    message_id = row.payload.dig('mail', 'messageId') if row.payload.is_a?(Hash) && row.payload['mail'].is_a?(Hash)
    message_id = row.recipient.ses_message_id if message_id.blank?
    key = "ses:#{message_id}:#{row.event_type}"
    message_id.present? && key.length <= 200 ? key : "historical:email_event:#{row.id}"
  end

  def from_legacy(row, account_id)
    raise ArgumentError, 'account_mismatch' unless row.account_id == account_id

    @email = row.email
    @occurred_at = row.created_at
    @event_key = "historical:email_suppression:#{row.id}"
    # Arbitrary legacy reasons remain untouched in the authoritative positive table.
    @reason = STRONG_REASONS.include?(row.reason) ? row.reason : 'manual'
    @metadata = { 'legacy_suppression_id' => row.id, 'evidence_code' => 'legacy_permanent_positive' }
  end
end
