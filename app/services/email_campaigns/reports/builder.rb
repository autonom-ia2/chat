class EmailCampaigns::Reports::Builder
  PEOPLE_LIMIT = 100
  TIMELINE_INTERVALS = %w[hour day].freeze
  TIMELINE_EVENT_TYPES = %w[delivered open click].freeze
  TIMELINE_CAP = 30.days

  def initialize(account:, params: {}, actor: nil)
    @account = account
    @actor = actor
    @query = EmailCampaigns::CampaignQuery.new(account: account, params: params)
  end

  def campaigns
    records.map do |campaign|
      metrics.by_campaign.fetch(campaign.id).merge(
        id: campaign.id, name: campaign.name, subject: campaign.subject, status: campaign.status, created_at: campaign.created_at,
        pause_reason: EmailCampaigns::Presentation::Protection.pause_reason(campaign)
      )
    end
  end

  def campaign_options
    @query.options.pluck(:id, :name, :status).map { |id, name, status| { id: id, name: name, status: status } }
  end

  def preflight
    return unless selected_campaign

    @preflight ||= EmailCampaigns::Presentation::Hygiene.new(selected_campaign, actor: @actor).call
  end

  def protection
    @protection ||= protection_presenter.call(campaign: selected_campaign, preflight: preflight)
  end

  def meta
    { count: records.size, applied_filters: applied_filters, delivery_evidence: metrics.summary.fetch(:delivery_evidence) }
  end

  def applied_filters
    @query.applied_filters
  end

  def summary
    metrics.summary
  end

  def campaign_detail(id)
    campaign = @query.call.find_by(id: id)
    return unless campaign

    values = EmailCampaigns::Reports::Metrics.new([campaign]).by_campaign.fetch(campaign.id)
    # Preserve legacy detail arrays; explicit counts prevent the opened/clicked
    # arrays from hiding their numeric KPI counterparts.
    hygiene = EmailCampaigns::Presentation::Hygiene.new(campaign, actor: @actor).call
    values.merge(id: campaign.id, name: campaign.name, subject: campaign.subject, status: campaign.status,
                 pause_reason: EmailCampaigns::Presentation::Protection.pause_reason(campaign),
                 meta: { delivery_evidence: values.fetch(:delivery_evidence) },
                 opened_count: values[:opened], clicked_count: values[:clicked],
                 opened: people(campaign, :open), clicked: people(campaign, :click),
                 preflight: hygiene, protection: protection_presenter.call(campaign: campaign, preflight: hygiene))
  end

  def clicks_by_url(campaign)
    campaign.email_events.clicks.where.not(url: [nil, '']).group(:url)
            .pluck(:url, Arel.sql('COUNT(*)'), Arel.sql('COUNT(DISTINCT recipient_id)'))
            .map { |url, total, unique| { url: url, total_clicks: total, unique_clicks: unique } }
            .sort_by { |row| [-row[:total_clicks], row[:url]] }
  end

  def timeline(campaign, interval: 'day')
    interval = TIMELINE_INTERVALS.include?(interval.to_s) ? interval.to_s : 'day'
    # Lower bound on created_at (sempre anterior a qualquer evento), NÃO em sent_at: no envio
    # direto os eventos ocorrem antes do finalize! (que grava sent_at=agora) e no SES os
    # 'delivered' que chegam durante um envio longo são anteriores ao sent_at final — usar
    # sent_at cortava esses eventos e zerava o gráfico.
    since = [campaign.created_at, TIMELINE_CAP.ago].max
    rows = campaign.email_events
                   .where(event_type: TIMELINE_EVENT_TYPES, occurred_at: since..Time.current)
                   .group(Arel.sql("date_trunc('#{interval}', occurred_at)"), :event_type)
                   .count
    buckets = Hash.new { |h, k| h[k] = { 'delivered' => 0, 'open' => 0, 'click' => 0 } }
    rows.each { |(bucket, type), count| buckets[bucket][type] = count }
    series = buckets.sort.map do |bucket, counts|
      { bucket: bucket.iso8601, delivered: counts['delivered'], open: counts['open'], click: counts['click'] }
    end
    { interval: interval, since: since.iso8601, series: series }
  end

  private

  def selected_campaign
    return unless applied_filters[:campaign_id]

    @selected_campaign ||= @query.options.find_by(id: applied_filters[:campaign_id])
  end

  def protection_presenter
    @protection_presenter ||= EmailCampaigns::Presentation::Protection.new(account: @account, actor: @actor)
  end

  def records
    @records ||= @query.call.to_a
  end

  def metrics
    @metrics ||= EmailCampaigns::Reports::Metrics.new(records)
  end

  def people(campaign, type)
    EmailCampaignRecipient.where(email_campaign_id: campaign.id)
                          .joins(:email_events)
                          .where(email_events: { event_type: EmailEvent.event_types[type.to_s] })
                          .distinct
                          .order(last_event_at: :desc, id: :asc)
                          .limit(PEOPLE_LIMIT)
                          .map { |r| { id: r.id, name: r.name, email: r.email, last_event_at: r.last_event_at } }
  end
end
