require 'rails_helper'

# Epic integration spec path is assigned to the reports workstream.
RSpec.describe EmailCampaigns::RecipientQuery do # rubocop:disable RSpec/SpecFilePathFormat
  let(:campaign) { create(:email_campaign) }

  it 'combines literal search, current status and attention before pagination and count' do
    target = create(:email_campaign_recipient, email_campaign: campaign, name: 'Literal %_\\ search', status: :failed)
    create(:email_campaign_recipient, email_campaign: campaign, name: 'Literal other search', status: :failed)
    create(:email_campaign_recipient, email_campaign: campaign, name: target.name, status: :unsubscribed)
    query = described_class.new(campaign, q: '%_\\', status: 'failed', problem: 'true')
    expect(query.call.pluck(:id)).to eq([target.id])
    expect(query.meta).to include(count: 1, current_page: 1, per_page: 50, total_pages: 1)
  end

  it 'ignores non-whitelisted scope and sorting parameters' do
    target = create(:email_campaign_recipient, email_campaign: campaign)
    other = create(:email_campaign_recipient)
    expect(described_class.new(campaign, account_id: other.email_campaign.account_id, order: 'email DESC').call.pluck(:id)).to eq([target.id])
  end

  [0, -1, '1.5', 'abc', [], {}, '1000001', '9' * 100].each do |page|
    it "rejects unsafe page #{page.inspect}" do
      expect { described_class.new(campaign, page: page) }.to raise_error(EmailCampaigns::Reports::Parameters::Invalid)
    end
  end

  [{ status: 'not_a_status' }, { status: ['sent'] }, { problem: 'anything' }, { q: { x: 'y' } }].each do |params|
    it "rejects invalid filters #{params.inspect}" do
      expect { described_class.new(campaign, params) }.to raise_error(EmailCampaigns::Reports::Parameters::Invalid)
    end
  end

  it 'sorts by id and paginates only after filtering' do
    rows = create_list(:email_campaign_recipient, 51, email_campaign: campaign, status: :failed)
    query = described_class.new(campaign, status: 'failed', page: '2')
    expect(query.paginated.pluck(:id)).to eq([rows.last.id])
    expect(query.meta).to include(count: 51, total_pages: 2)
  end

  it 'classifies the latest bounce using the shared classifier, with unknown retained evidence' do
    permanent = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced)
    temporary = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced)
    unknown = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced)
    provider = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced)
    permanent.email_events.create!(event_type: :bounce, occurred_at: 2.hours.ago, payload: { bounce: { bounceType: 'Transient' } })
    permanent.email_events.create!(event_type: :bounce, occurred_at: 1.hour.ago, payload: { bounce: { bounceType: 'Permanent' } })
    temporary.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Transient', bounceSubType: 'MailboxFull' } })
    provider.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'Suppressed' } })
    expect(described_class.new(campaign, status: 'hard_bounced').call.pluck(:id)).to eq([permanent.id, provider.id])
    expect(described_class.new(campaign, status: 'temporary_bounced').call.pluck(:id)).to eq([temporary.id])
    expect(described_class.new(campaign, status: 'unknown_bounced').call.pluck(:id)).to eq([unknown.id])
  end

  it 'does not treat cumulative delivered/opened evidence as a current status' do
    row = create(:email_campaign_recipient, email_campaign: campaign, status: :clicked, sent_at: 1.day.ago)
    %i[delivered open click].each { |type| row.email_events.create!(event_type: type) }
    expect(described_class.new(campaign, status: 'delivered').call).to be_empty
    expect(described_class.new(campaign, status: 'opened').call).to be_empty
    expect(described_class.new(campaign, status: 'clicked').call.pluck(:id)).to eq([row.id])
  end

  it 'gives protection precedence, excludes opt-out, and keeps preflight aliases on unsent pending rows' do
    invalid = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    sent = create(:email_campaign_recipient, email_campaign: campaign, status: :sent, sent_at: 1.day.ago, preflight_status: 'invalid')
    opted_out = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    EmailSuppression.create!(account: campaign.account, email: opted_out.email, reason: 'unsubscribe')
    expect(described_class.new(campaign, status: 'preflight_invalid').call.pluck(:id)).to eq([invalid.id])
    expect(described_class.new(campaign, problem: true).call.pluck(:id)).to eq([invalid.id])
    expect(described_class.new(campaign, problem: false).call.pluck(:id)).to eq([sent.id, opted_out.id])
  end

  it 'requires attention for unchecked/expired pending rows, but respects active protection and tenant boundaries' do
    expired = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.day.ago)
    unchecked = create(:email_campaign_recipient, email_campaign: campaign)
    valid = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid',
                                              preflight_checked_at: Time.current, preflight_valid_until: 1.day.from_now)
    protected_row = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.day.from_now)
    EmailSuppression.create!(account: campaign.account, email: protected_row.email, reason: 'manual')
    EmailSuppression.create!(account: create(:account), email: valid.email, reason: 'manual')
    expect(described_class.new(campaign, problem: true).call.pluck(:id)).to eq([expired.id, unchecked.id, protected_row.id])
  end

  it 'unions legacy positives and blocking states without letting expiry release opt-outs' do
    opt_outs = [1.hour.ago, 1.day.from_now].map do |expiry|
      row = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
      EmailSuppression.create!(account: campaign.account, email: row.email, reason: 'unsubscribe')
      EmailSuppressionState.create!(account: campaign.account, email: row.email, reason: 'temporary_failure', active: true, expires_at: expiry)
      row
    end
    temporary = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    expired = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    foreign = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    EmailSuppressionState.create!(account: campaign.account, email: temporary.email, reason: 'temporary_failure',
                                  active: true, expires_at: 1.day.from_now)
    EmailSuppressionState.create!(account: campaign.account, email: expired.email, reason: 'temporary_failure',
                                  active: true, expires_at: 1.hour.ago)
    EmailSuppressionState.create!(account: create(:account), email: foreign.email, reason: 'unsubscribe', active: true)
    expect(described_class.new(campaign, status: 'preflight_invalid').call.pluck(:id)).to eq([expired.id, foreign.id])
    expect(described_class.new(campaign, problem: true).call.pluck(:id)).to eq([temporary.id, expired.id, foreign.id])
    expect(described_class.new(campaign, problem: false).call.pluck(:id)).to eq(opt_outs.map(&:id))
  end

  it 'gives legacy reasons priority and retains active strong states even with a stale expiry' do
    legacy = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    state_only = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    inactive = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
    EmailSuppression.create!(account: campaign.account, email: legacy.email, reason: 'manual')
    [legacy, state_only].each do |row|
      EmailSuppressionState.create!(account: campaign.account, email: row.email, reason: 'unsubscribe', active: true, expires_at: 1.day.ago)
    end
    EmailSuppressionState.create!(account: campaign.account, email: inactive.email, reason: 'unsubscribe', active: false)
    expect(described_class.new(campaign, problem: true).call.pluck(:id)).to eq([legacy.id, inactive.id])
    expect(described_class.new(campaign, problem: false).call.pluck(:id)).to eq([state_only.id])
    expect(described_class.new(campaign, status: 'preflight_invalid').call.pluck(:id)).to eq([inactive.id])
  end

  it 'accepts nil filters and marks unchecked valid evidence and DNS-disabled unknown as attention' do
    unchecked = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.day.from_now)
    unknown = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'unknown',
                                                preflight_reason_code: 'dns_disabled', preflight_checked_at: Time.current)
    query = described_class.new(campaign, q: nil, status: nil, page: nil, problem: nil)
    expect(query.meta).to include(count: 2, current_page: 1, applied_filters: {})
    expect(described_class.new(campaign, problem: true).call.pluck(:id)).to eq([unchecked.id, unknown.id])
  end
end
