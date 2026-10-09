class EmailCampaigns::Presentation::Recipients
  def initialize(campaign, recipients)
    @campaign = campaign
    @recipients = recipients.to_a
  end

  def call
    return [] if @recipients.empty?

    load_batch
    @recipients.map { |recipient| present(recipient) }
  end

  private

  def load_batch
    ids = @recipients.map(&:id)
    scoped = @campaign.email_campaign_recipients.where(id: ids)
    @bounces = EmailCampaigns::Reports::BounceOutcomes.new(scoped).for_recipients
    @counts = EmailEvent.where(recipient_id: scoped.select(:id), event_type: %i[open click]).group(:recipient_id, :event_type).count
    @suppressions = EmailSuppression.blocking_reasons_for(@campaign.account, @recipients.map(&:email))
  end

  def present(recipient)
    evidence = @bounces[recipient.id]
    evidence ||= EmailCampaigns::BounceClassifier.call({}) if recipient.bounced?
    {
      id: recipient.id, name: recipient.name, email: recipient.email, status: recipient.status,
      attempts: recipient.attempts, last_event_at: recipient.last_event_at, sent_at: recipient.sent_at,
      opens: @counts.fetch([recipient.id, 'open'], 0), clicks: @counts.fetch([recipient.id, 'click'], 0),
      delivery_outcome: evidence&.fetch('classification'), reason_code: evidence&.fetch('reason_code'),
      preflight_status: recipient.preflight_status, preflight_reason: recipient.preflight_reason_code,
      preflight_suggestion: recipient.preflight_suggestion, preflight_valid_until: recipient.preflight_valid_until,
      suppression_reason: @suppressions[recipient.email.strip.downcase]
    }
  end
end
