require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::Admission do
  let(:account) { create(:account) }
  let(:identity) { EmailSenderIdentity.create!(account: account, domain: 'example.com', status: :verified) }
  let(:campaign) do
    EmailCampaign.create!(account: account, sender_identity: identity, name: 'Send', subject: 'Hello', body_html: '<p>Hello</p>', status: :sending)
  end
  let(:recipient) { campaign.email_campaign_recipients.create!(email: 'first@example.com') }
  let(:admission) { described_class.new(campaign) }

  before do
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(nil)
  end

  it 'does not query metrics during claims and only one claim owns a recipient' do
    expect(EmailCampaigns::Reputation::Metrics).not_to receive(:new)
    recipient # Materialize before observing admission SQL.
    queries = []
    subscriber = ->(*args) { queries << args.last[:sql] unless args.last[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      expect(admission.claim!(recipient)).to be(true)
      expect(described_class.new(EmailCampaign.find(campaign.id)).claim!(recipient)).to be(false)
    end
    expect(queries.grep(/COUNT\s*\(/i)).to be_empty
    expect(recipient.reload).to be_sent
    expect(recipient.sent_at).to be_nil
  end

  it 'observes a new persisted block despite the loaded account and parks before the next claim' do
    expect(admission.claim!(recipient)).to be(true)
    next_recipient = campaign.email_campaign_recipients.create!(email: 'next@example.com')
    Account.find(account.id).update!(internal_attributes: { email_campaigns_paused: { reason: 'legacy' } })
    expect(admission.claim!(next_recipient)).to be(false)
    expect(campaign.reload.pause_reason).to include('kind' => 'reputation', 'code' => 'legacy_pause')
    expect(next_recipient.reload).to be_pending
  end

  it 'limits override admissions across campaigns and does not refund already admitted calls' do
    state = EmailReputationState.create!(account: account, blocked: true, override: {
                                           actor_id: 123, remaining: 1, expires_at: 1.hour.from_now.iso8601
                                         })
    expect(admission.claim!(recipient)).to be(true)
    expect(state.reload.override['remaining']).to eq(0)
    next_recipient = campaign.email_campaign_recipients.create!(email: 'next@example.com')
    expect(admission.claim!(next_recipient)).to be(false)
    expect(EmailReputationAudit.where(account: account, action: 'override_budget_exhausted').count).to eq(1)
  end

  it 'cannot bypass the provider breaker with a tenant override' do
    EmailReputationState.create!(account: account, blocked: true, override: { remaining: 50, expires_at: 1.hour.from_now.iso8601 })
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(kind: 'provider', code: 'provider_blocked')
    expect(admission.claim!(recipient)).to be(false)
    expect(campaign.reload.pause_reason['kind']).to eq('provider')
  end

  it 'does not apply the SES breaker to direct inbox admission' do
    inbox = create(:channel_email, account: account).inbox
    campaign.update!(delivery_mode: :direct_inbox, sender_inbox: inbox)
    expect(EmailCampaigns::Reputation::ProviderGate).not_to receive(:protection)
    expect(admission.claim!(recipient)).to be(true)
  end

  it 'does not admit a manually paused campaign' do
    campaign.pause!
    expect(admission.claim!(recipient)).to be(false)
    expect(campaign.reload.pause_reason['kind']).to eq('manual')
  end

  it 'parks invalid policy configuration without sending' do
    with_modified_env('EMAIL_REPUTATION_MODE' => 'invalid') do
      expect(admission.park_if_blocked!).to be(true)
      expect(campaign.reload.pause_reason).to include('kind' => 'technical', 'code' => 'reputation_configuration_invalid')
    end
  end
end
