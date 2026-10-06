require 'rails_helper'

# #990 "Como foi esta campanha": the numbers of THIS campaign for a period (cohort by send date),
# with "all" equal to the totals the e-mail reports show at the top of the Resultado.
RSpec.describe CampaignJourney::EmailPeriodMetrics, :aggregate_failures do
  let(:now) { Time.zone.parse('2026-10-06 12:00') }
  let(:campaign) { create(:email_campaign, status: :paused) }
  let(:other_campaign) { create(:email_campaign, account: campaign.account, sender_identity: campaign.sender_identity, status: :sent) }

  def recipient(sent_at, status: :delivered, campaign: self.campaign)
    create(:email_campaign_recipient, email_campaign: campaign, status: status, sent_at: sent_at)
  end

  def bounce!(row, type)
    row.email_events.create!(event_type: :bounce, occurred_at: row.sent_at + 1.minute,
                             payload: { bounce: { bounceType: type, bounceSubType: 'General' } })
  end

  def complaint!(row)
    row.email_events.create!(event_type: :complaint, occurred_at: row.sent_at + 1.hour, payload: {})
  end

  before do
    recent = recipient(now - 2.days)
    bounce!(recipient(now - 3.days, status: :bounced), 'Permanent')
    complaint!(recent)
    bounce!(recipient(now - 10.days, status: :bounced), 'Transient')
    recipient(now - 20.days)
    bounce!(recipient(now - 40.days, status: :bounced), 'Permanent')
    recipient(nil, status: :pending)
    # Another campaign of the same account never leaks into this one.
    bounce!(recipient(now - 1.day, status: :bounced, campaign: other_campaign), 'Permanent')
  end

  def metrics(period)
    described_class.new(campaign, period: period, now: now).call
  end

  it 'counts only the people this campaign sent to inside each period' do
    expect(metrics('7')).to include(sent: 2, permanent_bounces: 1, temporary_bounces: 0, complaints: 1,
                                    hard_bounce_rate: 50.0, complaint_rate: 50.0, since: (now - 7.days).iso8601)
    expect(metrics('14')).to include(sent: 3, permanent_bounces: 1, temporary_bounces: 1, complaints: 1)
    expect(metrics('30')).to include(sent: 4, permanent_bounces: 1, temporary_bounces: 1, complaints: 1)
    expect(metrics('all')).to include(sent: 5, permanent_bounces: 2, temporary_bounces: 1, complaints: 1, since: nil,
                                      until: now.iso8601)
  end

  it 'matches the campaign totals of the e-mail reports for "all"' do
    top = EmailCampaigns::Reports::Metrics.new([campaign]).by_campaign.fetch(campaign.id)

    expect(metrics('all')).to include(sent: top[:sent], permanent_bounces: top[:permanent_bounced],
                                      temporary_bounces: top[:temporary_bounced], complaints: top[:complained],
                                      hard_bounce_rate: top[:hard_bounce_rate], complaint_rate: top[:complaint_rate])
  end

  it 'answers zero sends and no rate when the campaign sent nothing in the period' do
    campaign.email_campaign_recipients.where('sent_at > ?', now - 7.days).find_each { |row| row.update!(sent_at: now - 9.days) }

    expect(metrics('7')).to include(sent: 0, permanent_bounces: 0, complaints: 0, hard_bounce_rate: nil, complaint_rate: nil)
  end
end
