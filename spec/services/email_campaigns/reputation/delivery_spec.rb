require 'rails_helper'
require 'net/http'
require_relative '../../../../app/services/email_campaigns/ses/client'

RSpec.describe EmailCampaigns::DeliveryEngine do # rubocop:disable RSpec/SpecFilePathFormat -- reputation regression suite
  let(:account) { create(:account) }
  let(:identity) { EmailSenderIdentity.create!(account: account, domain: 'example.com', from_email: 'sender@example.com', status: :verified) }
  let(:campaign) do
    EmailCampaign.create!(account: account, sender_identity: identity, name: 'Send', subject: 'Hello', body_html: '<p>Hello</p>', status: :sending)
  end
  let!(:first) { campaign.email_campaign_recipients.create!(email: 'first@example.com') }
  let!(:second) { campaign.email_campaign_recipients.create!(email: 'second@example.com') }
  let(:sender) { instance_double(EmailCampaigns::Ses::Sender) }
  let(:engine) { described_class.new(campaign) }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(sender)
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(nil)
    allow(EmailCampaigns::Tracking::Injector).to receive(:new).and_return(instance_double(EmailCampaigns::Tracking::Injector,
                                                                                          perform: '<p>tracked</p>'))
    allow(EmailCampaigns::Unsubscribe::Token).to receive(:url).and_return('https://example.com/u/token')
    allow(engine).to receive(:sleep)
  end

  it 'finishes the in-flight send and admits no new recipient after observing a persisted block' do
    allow(sender).to receive(:deliver) do
      Account.find(account.id).update!(internal_attributes: { email_campaigns_paused: { reason: 'late feedback' } })
      'accepted-first'
    end
    expect(EmailCampaigns::Reputation::Metrics).not_to receive(:new)
    engine.perform
    expect(sender).to have_received(:deliver).once
    expect(first.reload.sent_at).to be_present
    expect(first.ses_message_id).to eq('accepted-first')
    expect(second.reload).to be_pending
    expect(campaign.reload).to be_paused
  end

  it 'rechecks persisted protection after rendering and before the claim' do
    allow(EmailCampaigns::Tracking::Injector).to receive(:new) do
      EmailReputationState.create!(account: account, blocked: true)
      instance_double(EmailCampaigns::Tracking::Injector, perform: '<p>tracked</p>')
    end
    expect(sender).not_to receive(:deliver)
    engine.perform
    expect(first.reload).to be_pending
    expect(campaign.reload).to be_paused
  end

  it 'never retries an ambiguous timeout or a post-acceptance bookkeeping failure' do
    allow(sender).to receive(:deliver).and_raise(Net::ReadTimeout, 'execution expired')
    engine.perform
    expect(first.reload).to be_failed
    expect(second.reload).to be_failed
    expect(first.sent_at).to be_nil
    expect(first.attempts).to eq(0)
  end

  it 'keeps the accepted claim when persistence fails' do
    allow(sender).to receive(:deliver).and_return('accepted')
    allow(EmailCampaigns::Tracking::Injector).to receive(:new) do |recipient, _html|
      allow(recipient).to receive(:update_columns).and_raise(ActiveRecord::StatementInvalid, 'synthetic failure')
      instance_double(EmailCampaigns::Tracking::Injector, perform: '<p>tracked</p>')
    end
    engine.perform
    expect(first.reload).to be_sent
    expect(second.reload).to be_sent
    expect(first.sent_at).to be_nil
    expect(first.attempts).to eq(0)
  end

  it 'never lets an override bypass contact suppression or consume its message budget' do
    state = EmailReputationState.create!(account: account, blocked: true,
                                         override: { actor_id: 123, remaining: 1, expires_at: 1.hour.from_now.iso8601 })
    EmailSuppression.create!(account: account, email: first.email, reason: 'complaint')
    allow(sender).to receive(:deliver).and_return('accepted-second')
    engine.perform
    expect(first.reload).to be_suppressed
    expect(sender).to have_received(:deliver).once.with(hash_including(to: second.email))
    expect(state.reload.override['remaining']).to eq(0)
  end

  it 'parks at job start without constructing a sender' do
    EmailReputationState.create!(account: account, blocked: true)
    expect(EmailCampaigns::Ses::Sender).not_to receive(:new)
    EmailCampaigns::DeliveryJob.perform_now(campaign.id)
    expect(campaign.reload).to be_paused
  end

  it 'rechecks contact suppression at admission after rendering' do
    allow(EmailCampaigns::Tracking::Injector).to receive(:new) do |recipient, _html|
      EmailSuppression.create!(account: account, email: recipient.email, reason: 'complaint')
      instance_double(EmailCampaigns::Tracking::Injector, perform: '<p>tracked</p>')
    end
    expect(sender).not_to receive(:deliver)
    engine.perform
    expect(first.reload).to be_suppressed
    expect(second.reload).to be_suppressed
  end
end
