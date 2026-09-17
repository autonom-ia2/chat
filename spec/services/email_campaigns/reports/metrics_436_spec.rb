require 'rails_helper'

# Epic integration spec path is assigned to the reports workstream.
RSpec.describe EmailCampaigns::Reports::Builder do # rubocop:disable RSpec/SpecFilePathFormat
  let(:campaign) { create(:email_campaign) }
  let(:builder) { described_class.new(account: campaign.account) }

  it 'counts distinct recipients and keeps repeated activity separate, including late events' do
    row = create(:email_campaign_recipient, email_campaign: campaign, status: :clicked, sent_at: 40.days.ago)
    %i[delivered open click bounce complaint unsubscribe].each do |type|
      2.times { row.email_events.create!(event_type: type, occurred_at: 1.hour.ago, payload: { bounce: { bounceType: 'Permanent' } }) }
    end
    summary = builder.summary
    expect(summary).to include(sent: 1, delivered: 1, opened: 1, clicked: 1, bounced: 1, complained: 1, unsubscribed: 1, permanent_bounces: 1)
    expect(summary[:activity]).to include('open' => 2, 'click' => 2, 'bounce' => 2)
    expect(summary[:current_status_counts]).to include('clicked' => 1, 'delivered' => 0)
    expect(builder.campaigns.first[:rates]).to eq(summary[:rates])
    expect(builder.campaign_detail(campaign.id)).to include(opened_count: 1, clicked_count: 1)
  end

  it 'reports no_data instead of healthy zero with no denominator' do
    expect(builder.summary[:open_rate]).to be_nil
    expect(builder.summary[:rate_metadata][:open_rate]).to include(status: 'no_data', denominator: 0)
    expect(builder.summary[:reputation_coverage]).to include(status: 'no_data', hard_bounce_rate: nil)
  end

  it 'uses accepted SES only for local reputation and accepted all modes for legacy bounce rate' do
    ses = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced, sent_at: 1.hour.ago)
    ses.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'General' } })
    ses.email_events.create!(event_type: :complaint)
    inbox = create(:inbox, :with_email, account: campaign.account)
    direct = create(:email_campaign, account: campaign.account, delivery_mode: :direct_inbox, sender_identity: nil, sender_inbox: inbox)
    create_list(:email_campaign_recipient, 3, email_campaign: direct, status: :sent, sent_at: 1.hour.ago)
    summary = builder.summary
    expect(summary).to include(sent: 4, bounce_rate: 25.0, hard_bounce_rate: 100.0, complaint_rate: 100.0)
    expect(summary[:reputation_coverage]).to include(sent: 1, excluded_direct_sent: 3, official_ses_ratio: false)
    expect(summary[:rate_metadata][:bounce_rate]).to include(basis: 'accepted_recipients', denominator: 4)
    expect(summary[:rate_metadata][:hard_bounce_rate]).to eq(
      value: 100.0, numerator: 1, denominator: 1, basis: 'ses_accepted_recipients', status: 'available'
    )
  end

  it 'separates provider prevention from permanent outcomes without calling it invalid mailbox' do
    row = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced, sent_at: 1.hour.ago)
    row.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'OnAccountSuppressionList' } })
    expect(builder.summary).to include(permanent_bounces: 0, unknown_bounces: 0, provider_prevented: 1, hard_bounce_rate: 0.0)
  end

  it 'keeps all account options independent of selection/status/search and filters only results' do
    second = create(:email_campaign, account: campaign.account, sender_identity: campaign.sender_identity, name: 'Second')
    paused = create(:email_campaign, account: campaign.account, sender_identity: campaign.sender_identity, status: :paused)
    foreign = create(:email_campaign)
    query = described_class.new(account: campaign.account, params: { campaign_id: campaign.id, campaign_status: 'draft', q: campaign.name })
    expect(query.campaigns.pluck(:id)).to eq([campaign.id])
    expect(query.campaign_options.pluck(:id)).to contain_exactly(campaign.id, second.id, paused.id)
    expect(query.campaign_detail(foreign.id)).to be_nil
    expect(EmailCampaigns::CampaignQuery.new(account: campaign.account,
                                             params: { q: 'Second',
                                                       status: 'draft' }).call.pluck(:id)).to eq([second.id])
  end

  it 'rejects unsupported dates and conflicting campaign filters instead of pretending to apply them' do
    [{ since: '2026-01-01' }, { until: '2026-01-01' }, { status: 'nope' }, { status: 'draft', campaign_status: 'paused' }].each do |params|
      expect { described_class.new(account: campaign.account, params: params) }.to raise_error(EmailCampaigns::Reports::Parameters::Invalid)
    end
  end

  it 'batches list metric reads independently of campaign count' do
    campaigns = create_list(:email_campaign, 4, account: campaign.account, sender_identity: campaign.sender_identity)
    campaigns.each { |row| create(:email_campaign_recipient, email_campaign: row) }
    queries = []
    subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i) && !payload[:cached] && payload[:name] != 'SCHEMA'
    end
    begin
      builder.summary
      builder.campaigns
      expect(queries.length).to be <= 5
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
  end

  it 'retains timeline activity preceding campaign completion and caps its lower bound at 30 days' do
    campaign.update!(created_at: 40.days.ago, sent_at: Time.current)
    row = create(:email_campaign_recipient, email_campaign: campaign)
    row.email_events.create!(event_type: :delivered, occurred_at: 1.day.ago)
    row.email_events.create!(event_type: :delivered, occurred_at: 35.days.ago)
    result = builder.timeline(campaign)
    expect(result[:series].sum { |point| point[:delivered] }).to eq(1)
    expect(Time.iso8601(result[:since])).to be_within(5.seconds).of(30.days.ago)
  end

  it 'reports unique URL clickers and raw activity without a human-click claim' do
    row = create(:email_campaign_recipient, email_campaign: campaign)
    2.times { row.email_events.create!(event_type: :click, url: 'https://example.org/docs') }
    expect(builder.clicks_by_url(campaign)).to eq([{ url: 'https://example.org/docs', total_clicks: 2, unique_clicks: 1 }])
  end

  it 'supports the UI attention campaign alias and rejects invalid campaign IDs' do
    paused = create(:email_campaign, account: campaign.account, sender_identity: campaign.sender_identity, status: :paused)
    failed = create(:email_campaign, account: campaign.account, sender_identity: campaign.sender_identity, status: :failed)
    query = EmailCampaigns::CampaignQuery.new(account: campaign.account, params: { campaign_status: 'attention' })
    expect(query.call.pluck(:id)).to contain_exactly(paused.id, failed.id)
    expect do
      EmailCampaigns::CampaignQuery.new(account: campaign.account, params: { campaign_id: 'abc' })
    end.to raise_error(EmailCampaigns::Reports::Parameters::Invalid)
  end

  it 'excludes unaccepted recipients from both sides of SES reputation rates' do
    recipient = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced)
    recipient.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent' } })
    recipient.email_events.create!(event_type: :complaint)
    expect(builder.summary[:reputation_coverage]).to include(sent: 0, permanent_bounces: 0, complaints: 0, hard_bounce_rate: nil)
    expect(builder.summary).to include(bounced: 1, complained: 1, bounce_rate: nil)
  end

  it 'retains permanent history after later prevention and counts each outcome once across duplicate subtypes' do
    row = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced, sent_at: 40.days.ago)
    %w[General NoEmail Suppressed General OnAccountSuppressionList OnTenantSuppressionList EmailValidationSuppressed
       UnsubscribedRecipient].each do |subtype|
      row.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: subtype } })
    end
    expect(builder.summary).to include(bounced: 1, permanent_bounces: 1, permanent_bounced: 1, temporary_bounced: 0,
                                       unknown_bounced: 0, provider_prevented: 1, hard_bounce_rate: 100.0)
    expect(builder.summary[:activity]['bounce']).to eq(8)
    expect(builder.summary[:reputation_coverage]).to include(permanent_bounces: 1, provider_prevented: 1, unknown_bounces: 0)
  end

  it 'counts global Suppressed as permanent while all four prevention subtypes remain separate' do
    %w[NoEmail Suppressed OnAccountSuppressionList OnTenantSuppressionList EmailValidationSuppressed UnsubscribedRecipient].each do |subtype|
      row = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced, sent_at: 1.hour.ago)
      row.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: subtype } })
    end
    expect(builder.summary).to include(sent: 6, bounced: 6, permanent_bounces: 2, unknown_bounces: 0, provider_prevented: 4,
                                       permanent_bounced: 2, hard_bounce_rate: 33.33)
  end

  it 'preserves legacy direct delivery counters while identifying acceptance as distinct from delivery evidence' do
    inbox = create(:inbox, :with_email, account: campaign.account)
    direct = create(:email_campaign, account: campaign.account, delivery_mode: :direct_inbox, sender_identity: nil, sender_inbox: inbox)
    row = create(:email_campaign_recipient, email_campaign: direct, status: :delivered, sent_at: 1.hour.ago)
    row.email_events.create!(event_type: :delivered, payload: { via: 'direct_inbox' })
    row.email_events.create!(event_type: :open)
    result = builder.campaigns.find { |item| item[:id] == direct.id }
    expect(result).to include(sent: 1, delivered: 1, open_rate: 100.0, hard_bounce_rate: nil)
    expect(result[:delivery_evidence]).to eq(provider_confirmed: 0, direct_acceptance_only: 1, legacy_delivered_includes_acceptance: true)
    expect(result[:reputation_coverage]).to include(sent: 0, excluded_direct_sent: 1, status: 'no_data')
  end
end
