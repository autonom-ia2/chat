# "Como foi esta campanha" of the e-mail Resultado (#990): the numbers of THIS campaign for a
# period, so the "Envio pausado" block stops showing the account's 7-day protection window as if
# it were the campaign. The period is a cohort by send date — the people this campaign sent to in
# the last N days, and what happened to them — the same cut the protection uses for its window.
# Counts come from EmailCampaigns::Reports::Metrics, so "all" equals the totals at the top.
class CampaignJourney::EmailPeriodMetrics
  PERIODS = { '7' => 7.days, '14' => 14.days, '30' => 30.days, 'all' => nil }.freeze
  DEFAULT_PERIOD = 'all'.freeze

  def initialize(campaign, period:, now: Time.current)
    @campaign = campaign
    @period = period
    @now = now
  end

  def call
    duration = PERIODS.fetch(@period)
    since = duration && (@now - duration)
    row = EmailCampaigns::Reports::Metrics.new([@campaign], sent_since: since).by_campaign.fetch(@campaign.id)
    {
      period: @period, since: since&.iso8601, until: @now.iso8601,
      sent: row[:sent], permanent_bounces: row[:permanent_bounced], temporary_bounces: row[:temporary_bounced],
      complaints: row[:complained], hard_bounce_rate: row[:hard_bounce_rate], complaint_rate: row[:complaint_rate]
    }
  end
end
