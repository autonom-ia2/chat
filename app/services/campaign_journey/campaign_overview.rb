# Gestão de campanhas as the multichannel overview (#1007, PRD D18, §6.10, O3): campaigns sent in a
# period, per channel, compared side by side. The detail of one campaign lives in its result.
#
# - "Enviadas" (a campaign is in the period) = it went out: e-mail not draft/scheduled, dated by
#   sent_at (else scheduled_at, else created_at); WhatsApp Oficial / SMS one-off processing or
#   completed, dated by scheduled_at; WhatsApp API not scheduled, dated by started_at (else scheduled_at).
# - "Pessoas alcançadas" = delivered (e-mail: provider delivery/acceptance events as in the e-mail
#   reports; WhatsApp Oficial and SMS: delivered or read). WhatsApp API has no delivery receipt, so
#   its accepted sends count.
# - "Responderam" = contacts whose conversation got the campaign mark (CampaignJourney::ResultReplies).
# - "Viraram negócio no CRM" = CRM cards linked to a conversation marked by these campaigns
#   (null when the CRM is off).
# - "Saúde do e-mail" = permanent bounce and complaint rates of these e-mail campaigns, over the SES
#   accepted sends, the same denominators the e-mail protection uses (limits 5% and 0.1%).
class CampaignJourney::CampaignOverview
  PERIODS = [7, 30, 90].freeze
  DEFAULT_PERIOD = 30
  PER_PAGE = 25
  # Totals read at most this many campaigns of the period (newest first).
  MAX_CAMPAIGNS = 500
  F = CampaignJourney::ResultFinder

  def initialize(account:, days: DEFAULT_PERIOD, channel: nil, page: 1)
    @account = account
    @days = PERIODS.include?(days.to_i) ? days.to_i : DEFAULT_PERIOD
    @channel = F::CHANNELS.include?(channel.to_s) ? channel.to_s : nil
    @page = [page.to_i, 1].max
  end

  def call
    rows = all_rows
    {
      period: { days: @days, since: since.iso8601, until: Time.current.iso8601 },
      channel: @channel,
      totals: totals(rows),
      campaigns: rows.slice((@page - 1) * PER_PAGE, PER_PAGE) || [],
      meta: { count: rows.size, current_page: @page, per_page: PER_PAGE, total_pages: (rows.size.to_f / PER_PAGE).ceil }
    }
  end

  private

  def since
    @since ||= @days.days.ago
  end

  def wanted?(channel)
    @channel.nil? || @channel == channel
  end

  def all_rows
    rows = []
    rows += email_rows if wanted?(F::EMAIL) && EmailCampaigns::Config.enabled?
    rows += chatwoot_rows if wanted?(F::WHATSAPP_OFFICIAL) || wanted?(F::SMS)
    rows += whatsapp_api_rows if wanted?(F::WHATSAPP_API)
    rows = rows.sort_by { |row| -row[:sent_at].to_i }.first(MAX_CAMPAIGNS)
    add_replies(rows)
  end

  def add_replies(rows)
    counts = CampaignJourney::ResultReplies.new(@account, rows.pluck(:source_id)).counts
    rows.map do |row|
      replied = counts.fetch(row[:source_id], 0)
      row.merge(replied: replied, reply_rate: rate(replied, row[:sent]))
    end
  end

  def totals(rows)
    emails = rows.select { |row| row[:channel] == F::EMAIL }
    {
      campaigns: rows.size,
      reached: rows.sum { |row| row[:delivered] || row[:sent] },
      replied: rows.sum { |row| row[:replied] },
      deals: Crm::Config.enabled? ? CampaignJourney::ResultReplies.new(@account, rows.pluck(:source_id)).deals : nil,
      email_health: emails.any? ? email_health : nil
    }
  end

  def rate(part, whole)
    whole.to_i.positive? ? (100.0 * part / whole).round(2) : nil
  end

  # ---- e-mail -------------------------------------------------------------------------------

  def email_campaigns
    sent_on = 'COALESCE(email_campaigns.sent_at, email_campaigns.scheduled_at, email_campaigns.created_at) >= ?'
    @email_campaigns ||= EmailCampaign.where(account_id: @account.id).where.not(status: %i[draft scheduled]).where(sent_on, since).to_a
  end

  def email_metrics
    @email_metrics ||= EmailCampaigns::Reports::Metrics.new(email_campaigns)
  end

  def email_rows
    metrics = email_metrics.by_campaign
    email_campaigns.map do |campaign|
      values = metrics.fetch(campaign.id)
      row = base_row(campaign, channel: F::EMAIL, id: campaign.id, name: campaign.name, status: campaign.status,
                               sent_at: campaign.sent_at || campaign.scheduled_at || campaign.created_at)
      row.merge(sent: values[:sent], delivered: values[:delivered],
                engagement: { kind: 'opened', count: values[:opened], rate: values[:open_rate] },
                email: values.slice(:click_rate, :hard_bounce_rate, :unsubscribe_rate))
    end
  end

  def email_health
    summary = email_metrics.summary
    { hard_bounce_rate: summary[:hard_bounce_rate], complaint_rate: summary[:complaint_rate],
      sent: summary.dig(:reputation_coverage, :sent), bounce_limit: 5.0, complaint_limit: 0.1 }
  end

  # ---- WhatsApp Oficial and SMS (Chatwoot one-off campaigns) ----------------------------------

  def chatwoot_rows
    campaigns = @account.campaigns.one_off.where(campaign_status: %i[processing completed])
                        .where(scheduled_at: since..).includes(inbox: :channel).to_a
                        .filter_map { |campaign| [campaign, F.channel_of(campaign)] }
                        .select { |(_campaign, channel)| channel && wanted?(channel) }
    counts = chatwoot_counts(campaigns.map(&:first))
    campaigns.map { |(campaign, channel)| chatwoot_row(campaign, channel, counts.fetch(campaign.id, {})) }
  end

  def chatwoot_counts(campaigns)
    return {} unless defined?(CampaignRecipient) && campaigns.any?

    CampaignRecipient.where(campaign_id: campaigns.map(&:id)).group(:campaign_id, :status).count
                     .each_with_object({}) { |((id, status), count), all| (all[id] ||= Hash.new(0))[status] += count }
  end

  def chatwoot_row(campaign, channel, counts)
    delivered = counts['delivered'].to_i + counts['read'].to_i
    sent = delivered + counts['sent'].to_i
    read = channel == F::WHATSAPP_OFFICIAL ? { kind: 'read', count: counts['read'].to_i, rate: rate(counts['read'].to_i, sent) } : nil
    base_row(campaign, channel: channel, id: campaign.display_id, name: campaign.title, status: campaign.campaign_status,
                       sent_at: campaign.scheduled_at)
      .merge(sent: sent, delivered: delivered, engagement: read, email: nil)
  end

  # ---- WhatsApp API ---------------------------------------------------------------------------

  def whatsapp_api_rows
    return [] unless WhatsappApiCampaigns::Config.enabled?

    WhatsappApiCampaign.where(account_id: @account.id).where.not(status: :scheduled)
                       .where('COALESCE(whatsapp_api_campaigns.started_at, whatsapp_api_campaigns.scheduled_at) >= ?', since)
                       .map do |campaign|
      base_row(campaign, channel: F::WHATSAPP_API, id: campaign.id, name: campaign.title, status: campaign.status,
                         sent_at: campaign.started_at || campaign.scheduled_at)
        .merge(sent: campaign.sent_count, delivered: nil, engagement: nil, email: nil)
    end
  end

  # attributes: channel, id (the one the result route uses), name, status, sent_at
  def base_row(campaign, **attributes)
    attributes.merge(source_id: CampaignJourney::CampaignMarks.source_id_for(campaign))
  end
end
