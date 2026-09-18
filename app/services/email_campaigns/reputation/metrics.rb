require 'digest'

class EmailCampaigns::Reputation::Metrics
  # Global Suppressed still counts toward SES bounce reputation; it is not mailbox-not-found evidence.
  PREVENTED_SQL = <<~SQL.squish.freeze
    COALESCE(payload #>> '{bounce,bounceSubType}', '') IN
    ('OnAccountSuppressionList', 'OnTenantSuppressionList', 'EmailValidationSuppressed', 'UnsubscribedRecipient')
  SQL
  PERMANENT_SQL = "payload #>> '{bounce,bounceType}' = 'Permanent' AND NOT (#{PREVENTED_SQL})".freeze
  COUNT_FILTERS = {
    permanent: "event_type = 3 AND (#{PERMANENT_SQL})",
    transient: "event_type = 3 AND NOT (#{PREVENTED_SQL}) AND payload #>> '{bounce,bounceType}' = 'Transient'",
    unknown: "event_type = 3 AND NOT (#{PREVENTED_SQL}) AND COALESCE(payload #>> '{bounce,bounceType}', '') NOT IN ('Permanent', 'Transient')",
    provider_prevented: "(event_type = 3 AND (#{PREVENTED_SQL})) OR (#{EmailCampaigns::ComplaintClassifier::PROVIDER_PREVENTED_SQL})",
    bounced: "event_type = 3 AND NOT (#{PREVENTED_SQL})", complaints: EmailCampaigns::ComplaintClassifier::REAL_COMPLAINT_SQL
  }.freeze

  def initialize(account_id, now: Time.current)
    @account_id = account_id
    @now = now
  end

  # One grouped query for all cohort counts; prevention is not an original bounce.
  def call
    flags = COUNT_FILTERS.map { |name, predicate| "BOOL_OR(#{predicate}) AS #{name}" }.join(', ')
    counts = COUNT_FILTERS.keys.map { |name| "COUNT(*) FILTER (WHERE #{name}) AS #{name}" }.join(', ')
    sql = <<~SQL.squish
      SELECT COUNT(*) AS sent, #{counts} FROM (
        SELECT email_campaign_recipients.id, #{flags}
        FROM (#{cohort.to_sql}) email_campaign_recipients
        LEFT JOIN email_events ON email_events.recipient_id = email_campaign_recipients.id
        GROUP BY email_campaign_recipients.id
      ) outcomes
    SQL
    result = EmailEvent.connection.select_one(sql).symbolize_keys.transform_values(&:to_i)
    result.merge(cohort_start: (@now - EmailCampaigns::Reputation::Policy::WINDOW_SECONDS).iso8601,
                 cohort_end: @now.iso8601, scope: 'local_ses_sending_cohort', window_days: 7)
  end

  # Fixed-size SQL summary of distinct harmful outcomes across accepted history.
  # Duplicate notifications are stable; classification corrections change the set.
  # Numeric sums do not overflow bigint; neither SQL nor Ruby builds an array/JSON of history.
  def harmful_feedback_fingerprint
    keys = harmful_events.select("DISTINCT recipient_id, event_type, COALESCE(payload #>> '{bounce,bounceSubType}', '') AS subtype, " \
                                 "COALESCE(payload #>> '{complaint,complaintFeedbackType}', '') AS complaint_type")
    sql = <<~SQL.squish
      SELECT COUNT(*) AS count,
        COALESCE(SUM(('x' || SUBSTR(hash, 1, 16))::bit(64)::bigint::numeric), 0) AS high,
        COALESCE(SUM(('x' || SUBSTR(hash, 17, 16))::bit(64)::bigint::numeric), 0) AS low
      FROM (SELECT MD5(recipient_id::text || ':' || event_type::text || ':' || subtype || ':' || complaint_type) AS hash
            FROM (#{keys.to_sql}) distinct_outcomes) hashes
    SQL
    Digest::SHA256.hexdigest(EmailEvent.connection.select_one(sql).values.map(&:to_s).join(':'))
  end

  private

  def cohort
    EmailCampaignRecipient.joins(:email_campaign)
                          .where(email_campaigns: { account_id: @account_id, delivery_mode: :ses })
                          .where(sent_at: (@now - EmailCampaigns::Reputation::Policy::WINDOW_SECONDS)..@now)
                          .select('email_campaign_recipients.id')
  end

  def harmful_events
    EmailEvent.joins(recipient: :email_campaign)
              .where(email_campaigns: { account_id: @account_id, delivery_mode: :ses })
              .where.not(email_campaign_recipients: { sent_at: nil })
              .where("(#{EmailCampaigns::ComplaintClassifier::REAL_COMPLAINT_SQL}) OR (email_events.event_type = 3 AND (#{PERMANENT_SQL}))")
  end
end
