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
    @outcomes = EmailCampaigns::Reports::RecipientOutcomes.new(scoped).call
    @counts = EmailEvent.where(recipient_id: scoped.select(:id), event_type: %i[open click]).group(:recipient_id, :event_type).count
    @suppressions = EmailSuppression.blocking_reasons_for(@campaign.account, @recipients.map(&:email))
    @opted_out_emails = opted_out_emails
  end

  def present(recipient)
    {
      id: recipient.id, name: recipient.name, email: recipient.email, delivery_mode: @campaign.delivery_mode,
      attempts: recipient.attempts, last_event_at: recipient.last_event_at, sent_at: recipient.sent_at,
      opens: @counts.fetch([recipient.id, 'open'], 0), clicks: @counts.fetch([recipient.id, 'click'], 0),
      preflight_status: recipient.preflight_status, preflight_reason: recipient.preflight_reason_code,
      preflight_suggestion: recipient.preflight_suggestion, preflight_valid_until: recipient.preflight_valid_until,
      suppression_reason: suppression_reason(recipient.email.strip.downcase)
    }.merge(delivery_presentation(recipient))
  end

  # A recusa do contato (chat#737) aparece como opt_out quando não há outro motivo de supressão registrado.
  def suppression_reason(email)
    @suppressions[email] || ('opt_out' if @opted_out_emails.include?(email))
  end

  def opted_out_emails
    emails = @recipients.map { |recipient| recipient.email.strip.downcase }.uniq
    @campaign.account.contacts.opted_out.where('lower(email) IN (?)', emails).pluck(Arel.sql('lower(email)')).to_set
  end

  def delivery_presentation(recipient)
    outcome = @outcomes.fetch(recipient.id, {})
    if outcome[:complaint_prevented] && !recipient.unsubscribed? && !recipient.complained?
      return { status: 'suppressed', delivery_outcome: 'unknown', reason_code: 'provider_suppression' }
    end

    evidence = outcome[:bounce]
    evidence ||= EmailCampaigns::BounceClassifier.call({}) if recipient.bounced?
    { status: recipient.status, delivery_outcome: evidence&.fetch('classification'), reason_code: evidence&.fetch('reason_code') }
  end
end
