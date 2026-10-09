class EmailCampaigns::SuppressionRegistry
  PRIORITY = { 'temporary_failure' => 1, 'provider_suppression' => 2, 'hard_bounce' => 3,
               'manual' => 4, 'complaint' => 5, 'unsubscribe' => 6 }.freeze
  RECORD_REASONS = (PRIORITY.keys + %w[unknown_bounce]).freeze
  Result = Struct.new(:suppression, :event, :duplicate, keyword_init: true)

  def initialize(account:, email:, campaign: nil, config: EmailCampaigns::HygieneConfig.new)
    raise ArgumentError, 'campaign account mismatch' if campaign && campaign.account_id != account.id

    @account = account
    @email = EmailCampaigns::EmailNormalizer.normalize!(email).email
    @campaign = campaign
    @config = config
  end

  def block!(reason:, **attributes)
    raise ArgumentError, 'block requires a strong reason' unless PRIORITY.key?(reason) && reason != 'temporary_failure'

    record!(reason: reason, **attributes)
  end

  def record!(reason:, source:, event_key:, occurred_at: Time.current, metadata: {})
    raise ArgumentError, 'invalid reason' unless RECORD_REASONS.include?(reason)

    write(reason: reason, source: source, event_key: event_key, occurred_at: occurred_at, metadata: metadata, action: 'record') do |row|
      apply_block(row, reason, source, occurred_at)
      mirror_permanent!(reason, source) if PRIORITY.key?(reason) && reason != 'temporary_failure'
    end
  end

  # An arbitrary approval reference can never clear a legacy positive or consent/spam.
  # No verified resubscribe flow is implemented in PR0.
  def release!(source:, event_key:, authorization:, occurred_at: Time.current)
    raise ArgumentError, 'release requires authorization reference' if authorization.blank?

    write(reason: 'authorized_release', source: source, event_key: event_key, occurred_at: occurred_at,
          metadata: { 'authorization' => authorization }, action: 'release') do |row|
      raise ArgumentError, 'only unmirrored manual state can be released' unless row.reason == 'manual' && !legacy_scope.exists?

      row.active = false
      row.expires_at = nil
    end
  end

  private

  def write(attributes)
    key = attributes.fetch(:event_key)
    raise ArgumentError, 'event_key required (max 200)' if key.blank? || key.length > 200
    raise ArgumentError, 'source required' if attributes.fetch(:source).blank?

    EmailSuppressionState.transaction do
      row = locked_state
      existing = row.email_suppression_events.find_by(event_key: key)
      next Result.new(suppression: row, event: existing, duplicate: true) if existing

      event = append_event(row, attributes)
      yield row
      row.save!
      Result.new(suppression: row, event: event, duplicate: false)
    end
  end

  def locked_state
    # Atomic first insert serializes parallel replay without occupying the legacy key.
    EmailSuppressionState.insert_all( # rubocop:disable Rails/SkipsModelValidations
      [{ account_id: @account.id, email: @email, created_at: Time.current }], unique_by: 'idx_suppression_states_account_email'
    )
    EmailSuppressionState.where(account_id: @account.id, email: @email).lock.first!
  end

  def append_event(row, attributes)
    occurred_at = attributes.fetch(:occurred_at)
    row.first_seen_at = [row.first_seen_at || occurred_at, occurred_at].min
    row.last_seen_at = [row.last_seen_at || occurred_at, occurred_at].max
    row.occurrences += 1
    row.email_suppression_events.create!(**attributes, account: @account, origin_campaign_id: @campaign&.id,
                                                       first_seen_at: occurred_at, last_seen_at: occurred_at, created_at: Time.current)
  end

  def legacy_scope
    EmailSuppression.where(account_id: @account.id).where('lower(email) = ?', @email)
  end

  def mirror_permanent!(reason, source)
    # Old writers can insert concurrently; conflict preserves their positive row.
    EmailSuppression.insert_all( # rubocop:disable Rails/SkipsModelValidations
      [{ account_id: @account.id, email: @email, reason: reason, source: source, created_at: Time.current }],
      unique_by: 'idx_email_suppressions_account_email'
    )
    legacy = legacy_scope.lock.first!
    legacy.update!(reason: reason, source: source) if PRIORITY.fetch(reason) > PRIORITY.fetch(legacy.reason, 7)
  end

  def apply_block(row, reason, source, occurred_at)
    return unless PRIORITY.key?(reason)
    return if stronger_state?(row, reason)
    return if reason == 'temporary_failure' && !quarantine_due?(row)

    row.assign_attributes(active: true, reason: reason, source: source, origin_campaign_id: @campaign&.id || row.origin_campaign_id)
    row.expires_at = quarantine_expiry(row, reason, occurred_at)
  end

  def stronger_state?(row, reason)
    row.active && row.reason != 'temporary_failure' && PRIORITY.fetch(row.reason, 7) >= PRIORITY.fetch(reason)
  end

  def quarantine_expiry(row, reason, occurred_at)
    [row.expires_at, occurred_at + @config.quarantine_duration].compact.max if reason == 'temporary_failure'
  end

  def quarantine_due?(row)
    row.email_suppression_events.where(action: 'record', reason: 'temporary_failure')
       .where(occurred_at: (Time.current - @config.temporary_window)..Time.current)
       .limit(@config.temporary_threshold).count >= @config.temporary_threshold
  end
end
