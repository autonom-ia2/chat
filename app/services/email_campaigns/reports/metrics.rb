class EmailCampaigns::Reports::Metrics
  COUNTERS = %i[recipients sent delivered opened clicked bounced complained unsubscribed failed suppressed
                permanent_bounces temporary_bounces unknown_bounces provider_prevented provider_confirmed_delivered direct_acceptance_events].freeze
  EVENTS = { 'delivered' => :delivered, 'open' => :opened, 'click' => :clicked, 'bounce' => :bounced,
             'complaint' => :complained, 'unsubscribe' => :unsubscribed }.freeze

  def initialize(campaigns)
    @campaigns = campaigns
    @recipients = EmailCampaignRecipient.where(email_campaign_id: campaigns.map(&:id))
    @ses_ids = campaigns.select(&:ses?).to_set(&:id)
  end

  def by_campaign
    @by_campaign ||= begin
      @data = @campaigns.to_h { |campaign| [campaign.id, empty] }
      load_recipients
      load_events
      load_bounces
      @data.transform_values { |row| present(row) }
    end
  end

  def summary
    by_campaign
    total = empty
    @data.each_value do |row|
      COUNTERS.each { |key| total[key] += row[key] }
      %i[current_status_counts activity reputation_counts].each do |key|
        row[key].each { |name, count| total[key][name] = total[key].fetch(name, 0) + count }
      end
    end
    present(total)
  end

  private

  def empty
    COUNTERS.index_with(0).merge(current_status_counts: EmailCampaignRecipient.statuses.keys.index_with(0),
                                 activity: EVENTS.keys.index_with(0),
                                 reputation_counts: { sent: 0, permanent_bounces: 0, temporary_bounces: 0,
                                                      unknown_bounces: 0, provider_prevented: 0, complaints: 0 })
  end

  def load_recipients
    @recipients.group(:email_campaign_id, :status, Arel.sql('sent_at IS NOT NULL')).count.each do |(id, status, accepted), count|
      row = @data.fetch(id)
      row[:recipients] += count
      row[:current_status_counts][status] += count
      row[status.to_sym] += count if %w[failed suppressed].include?(status)
      next unless accepted

      row[:sent] += count
      row[:reputation_counts][:sent] += count if @ses_ids.include?(id)
    end
  end

  def load_events
    # Fixed-size aggregates: raw activity retains prevention notifications, while
    # complaint KPIs use real complaints and prevention is distinct across BOTH types.
    prevented = EmailCampaigns::Reputation::Metrics::COUNT_FILTERS.fetch(:provider_prevented)
    EmailEvent.joins(:recipient).where(recipient_id: @recipients.select(:id))
              .group('email_campaign_recipients.email_campaign_id', Arel.sql('email_campaign_recipients.sent_at IS NOT NULL'))
              .pluck(Arel.sql('email_campaign_recipients.email_campaign_id'), Arel.sql('email_campaign_recipients.sent_at IS NOT NULL'),
                     Arel.sql("COUNT(DISTINCT recipient_id) FILTER (WHERE #{prevented})"), *event_counts_sql)
              .each do |id, accepted, prevention, *counts|
      EVENTS.each_key.with_index { |type, index| add_event_counts(id, type, accepted, *counts.slice(index * 2, 2)) }
      @data.fetch(id)[:provider_prevented] += prevention
      @data.fetch(id)[:reputation_counts][:provider_prevented] += prevention if accepted && @ses_ids.include?(id)
    end
  end

  def event_counts_sql
    EVENTS.keys.flat_map do |type|
      activity = "event_type = #{EmailEvent.event_types.fetch(type)}"
      unique = type == 'complaint' ? EmailCampaigns::ComplaintClassifier::REAL_COMPLAINT_SQL : activity
      [Arel.sql("COUNT(*) FILTER (WHERE #{activity})"), Arel.sql("COUNT(DISTINCT recipient_id) FILTER (WHERE #{unique})")]
    end
  end

  def add_event_counts(id, type, accepted, activity, unique)
    row = @data.fetch(id)
    row[EVENTS.fetch(type)] += unique
    row[:activity][type] += activity
    row[@ses_ids.include?(id) ? :provider_confirmed_delivered : :direct_acceptance_events] += unique if type == 'delivered'
    row[:reputation_counts][:complaints] += unique if type == 'complaint' && accepted && @ses_ids.include?(id)
  end

  def load_bounces
    EmailCampaigns::Reports::BounceOutcomes.new(@recipients).grouped.each do |(id, classification, accepted), count|
      next if classification == 'provider_prevented' # Already counted across bounce + complaint in load_events.

      key = "#{classification}_bounces".to_sym
      row = @data.fetch(id)
      row[key] += count
      row[:reputation_counts][key] += count if accepted && @ses_ids.include?(id)
    end
  end

  def present(row)
    rate_data = rate_bases(row).transform_values do |numerator, denominator, basis|
      { value: percent(numerator, denominator), numerator: numerator, denominator: denominator, basis: basis,
        status: denominator.zero? ? 'no_data' : 'available' }
    end
    rates = rate_data.transform_values { |value| value[:value] }
    row.except(:reputation_counts).merge(rates).merge(
      permanent_bounced: row[:permanent_bounces], temporary_bounced: row[:temporary_bounces], unknown_bounced: row[:unknown_bounces],
      delivery_evidence: delivery_evidence(row), rates: rates, rate_metadata: rate_data, metric_scope: 'campaign_recipient_cohort_all_events',
      reputation_coverage: reputation_coverage(row, rates)
    )
  end

  def delivery_evidence(row)
    { provider_confirmed: row[:provider_confirmed_delivered], direct_acceptance_only: row[:direct_acceptance_events],
      legacy_delivered_includes_acceptance: row[:direct_acceptance_events].positive? }
  end

  def rate_bases(row)
    {
      open_rate: [row[:opened], row[:delivered], 'legacy_delivered_events_including_direct_acceptance'],
      click_rate: [row[:clicked], row[:delivered], 'legacy_delivered_events_including_direct_acceptance'],
      unsubscribe_rate: [row[:unsubscribed], row[:delivered], 'legacy_delivered_events_including_direct_acceptance'],
      bounce_rate: [row[:bounced], row[:sent], 'accepted_recipients'],
      hard_bounce_rate: [row[:reputation_counts][:permanent_bounces], row[:reputation_counts][:sent], 'ses_accepted_recipients'],
      complaint_rate: [row[:reputation_counts][:complaints], row[:reputation_counts][:sent], 'ses_accepted_recipients']
    }
  end

  def reputation_coverage(row, rates)
    row[:reputation_counts].merge(
      scope: 'selected_ses_campaigns', accepted_basis: 'recipient_sent_at', excluded_direct_sent: row[:sent] - row[:reputation_counts][:sent],
      status: row[:reputation_counts][:sent].zero? ? 'no_data' : 'available', official_ses_ratio: false,
      hard_bounce_rate: rates[:hard_bounce_rate], complaint_rate: rates[:complaint_rate]
    )
  end

  def percent(numerator, denominator)
    return if denominator.zero?

    (100.0 * numerator / denominator).round(2)
  end
end
