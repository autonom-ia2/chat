# Classifications come from the admission/SNS classifier. Latest evidence serves
# recipient filters; historical DISTINCT counts serve KPIs. No second taxonomy.
class EmailCampaigns::Reports::BounceOutcomes
  def initialize(recipients)
    @recipients = recipients.reorder(nil)
  end

  def latest
    EmailEvent.where(event_type: :bounce, recipient_id: @recipients.select(:id))
              .select(Arel.sql("DISTINCT ON (recipient_id) recipient_id, payload -> 'bounce' AS bounce"))
              .order(:recipient_id, occurred_at: :desc, id: :desc)
  end

  def evidence
    EmailEvent.unscoped.from("(#{latest.to_sql}) latest_bounces")
  end

  def matching(classification)
    expression = "jsonb_build_object('bounceType', bounce ->> 'bounceType', 'bounceSubType', bounce ->> 'bounceSubType')"
    pairs = evidence.distinct.pluck(Arel.sql(expression))
    pairs.select! { |pair| EmailCampaigns::BounceClassifier.call(pair).fetch('classification') == classification }
    return @recipients.none if pairs.empty? && classification != 'unknown'

    clauses = pairs.map do |pair|
      EmailEvent.sanitize_sql_array(["#{expression} = ?::jsonb", pair.to_json])
    end
    ids = evidence.where(clauses.empty? ? 'FALSE' : clauses.join(' OR ')).select('recipient_id')
    result = @recipients.where(id: ids)
    # Old bounced rows without retained evidence must remain visible as unknown.
    result = result.or(@recipients.where.not(id: evidence.select('recipient_id'))) if classification == 'unknown'
    result
  end

  # History is distinct per recipient/outcome, unlike the latest evidence used by
  # the recipient table. One later prevention notification cannot erase an earlier bounce.
  def grouped
    EmailEvent.joins(:recipient).where(event_type: :bounce, recipient_id: @recipients.select(:id))
              .group('email_campaign_recipients.email_campaign_id', Arel.sql(classification_sql),
                     Arel.sql('email_campaign_recipients.sent_at IS NOT NULL')).distinct.count(:recipient_id)
  end

  private

  def classification_sql
    classifier = EmailCampaigns::BounceClassifier
    clauses = classifier::SUBTYPE_OUTCOMES.keys.map do |subtype|
      outcome = classifier.call('bounceSubType' => subtype).fetch('classification')
      EmailEvent.sanitize_sql_array(["WHEN payload #>> '{bounce,bounceSubType}' = ? THEN ?", subtype, outcome])
    end
    %w[Permanent Transient].each do |type|
      outcome = classifier.call('bounceType' => type).fetch('classification')
      clauses << EmailEvent.sanitize_sql_array(["WHEN payload #>> '{bounce,bounceType}' = ? THEN ?", type, outcome])
    end
    # Reuse PR1's exact prevention contract, never a divergent local list.
    prevented = EmailCampaigns::Reputation::Metrics::PREVENTED_SQL
    fallback = EmailEvent.sanitize_sql_array(['ELSE ? END', classifier.call({}).fetch('classification')])
    "CASE WHEN #{prevented} THEN 'provider_prevented' #{clauses.join(' ')} #{fallback}"
  end
end
