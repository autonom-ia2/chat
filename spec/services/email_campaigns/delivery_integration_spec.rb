require 'rails_helper'
require 'net/http'

RSpec.describe 'Integrated hygiene and reputation delivery', type: :model do
  let(:campaign) { create(:email_campaign, status: :sending) }
  let(:account) { campaign.account }
  let!(:recipient) { create(:email_campaign_recipient, email_campaign: campaign) }
  let(:sender) { instance_double(EmailCampaigns::Ses::Sender, deliver: 'accepted-synthetic') }
  let(:engine) { EmailCampaigns::DeliveryEngine.new(campaign) }
  let(:admission) { EmailCampaigns::Reputation::Admission.new(campaign) }

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_REPUTATION_MODE' => 'shadow',
                      'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false', 'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false',
                      'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '') { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(sender)
    allow(EmailCampaigns::Unsubscribe::Token).to receive(:url).and_return('https://example.org/u/synthetic')
    allow(EmailCampaigns::Tracking::Injector).to receive(:new).and_return(
      instance_double(EmailCampaigns::Tracking::Injector, perform: '<p>Synthetic</p>')
    )
    allow(engine).to receive(:sleep)
  end

  it 'cannot use a tenant override to claim an unvalidated destination or spend its budget' do
    state = EmailReputationState.create!(account: account, blocked: true,
                                         override: { remaining: 1, actor_id: 123, expires_at: 1.hour.from_now.iso8601 })
    expect(admission.claim!(recipient)).to be(false)
    expect(recipient.reload).to be_pending
    expect(state.reload.override.fetch('remaining')).to eq(1)
    expect(campaign.reload.hygiene_pause_reason).to eq('hygiene_validation_required')
  end

  it 'revalidates expired hygiene evidence after rendering, before final admission' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(engine).to receive(:render) do
      EmailCampaignRecipient.find(recipient.id).update!(preflight_valid_until: 1.second.ago)
      { subject: 'Synthetic', body_html: '<p>Synthetic</p>' }
    end
    engine.perform
    expect(sender).not_to have_received(:deliver)
    expect(recipient.reload).to be_pending
    expect(campaign.reload).to be_paused
  end

  it 'stops before the next claim after a tenant flag, preserving the accepted in-flight message' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    next_recipient = create(:email_campaign_recipient, email_campaign: campaign,
                                                       preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(sender).to receive(:deliver) do
      Account.find(account.id).update!(internal_attributes: { email_campaigns_paused: { reason: 'synthetic' } })
      'accepted-before-block'
    end
    engine.perform
    expect(sender).to have_received(:deliver).once
    expect(recipient.reload.ses_message_id).to eq('accepted-before-block')
    expect(next_recipient.reload).to be_pending
    expect(campaign.reload.pause_reason).to include('kind' => 'reputation')
  end

  it 'stops before the next claim after a durable provider block even with monitoring disabled' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    next_recipient = create(:email_campaign_recipient, email_campaign: campaign,
                                                       preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(sender).to receive(:deliver) do
      EmailProviderState.create!(provider_key: EmailCampaigns::Reputation::ProviderConfig.new.provider_key, status: 'healthy', blocked: true)
      'accepted-before-block'
    end
    engine.perform
    expect(sender).to have_received(:deliver).once
    expect(recipient.reload.sent_at).to be_present
    expect(next_recipient.reload).to be_pending
    expect(campaign.reload.pause_reason).to include('kind' => 'provider')
  end

  %w[queued processing].each do |status|
    it "refuses direct admission during an active #{status} import" do
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      campaign.email_campaign_imports.create!(status: status)
      expect(admission.claim!(recipient)).to be(false)
      expect(recipient.reload).to be_pending
    end
  end

  it 'sees an import started during rendering and leaves the never-dispatched recipient pending' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(engine).to receive(:render) do
      campaign.email_campaign_imports.create!(status: :processing)
      { subject: 'Synthetic', body_html: '<p>Synthetic</p>' }
    end
    engine.perform
    expect(sender).not_to have_received(:deliver)
    expect(recipient.reload).to be_pending
    expect(campaign.reload).to be_sending
  end

  it 'retains dispatch history and tenant protection across duplicate import and a new campaign' do
    recipient.update!(status: :delivered, ses_message_id: 'old-acceptance', sent_at: 1.day.ago)
    before_import = recipient.attributes
    state = EmailReputationState.create!(account: account, blocked: true,
                                         triggered_at: 1.hour.ago, trigger_snapshot: { code: 'synthetic_incident' })
    csv = "name,email\nSynthetic,#{recipient.email}\n"
    result = EmailCampaigns::RecipientImporter.new(campaign, csv, filename: 'synthetic.csv').perform
    expect(result.duplicates).to eq(1)
    expect(recipient.reload.attributes).to eq(before_import)
    future = create(:email_campaign, account: account, sender_identity: campaign.sender_identity, status: :sending)
    EmailCampaigns::RecipientImporter.new(future, csv, filename: 'synthetic.csv').perform
    pending = future.email_campaign_recipients.sole
    pending.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    expect(EmailCampaigns::Reputation::Admission.new(future).claim!(pending)).to be(false)
    expect(state.reload).to be_blocked
    expect(state.trigger_snapshot).to eq('code' => 'synthetic_incident')
    expect(pending.reload).to be_pending
  end

  it 'does not turn a competing claim into failed when rendering raises' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(engine).to receive(:render) do
      expect(EmailCampaigns::Reputation::Admission.new(EmailCampaign.find(campaign.id)).claim!(EmailCampaignRecipient.find(recipient.id))).to be(true)
      raise 'synthetic rendering error'
    end
    engine.send(:deliver_one, recipient, sender)
    expect(recipient.reload).to be_sent
    expect(recipient.last_error).to be_nil
    expect(sender).not_to have_received(:deliver)
  end

  it 'preserves an opt-out committed while a provider failure is in flight' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(sender).to receive(:deliver) do
      EmailCampaignRecipient.find(recipient.id).update!(status: :unsubscribed)
      raise Net::ReadTimeout, 'synthetic timeout'
    end
    engine.perform
    expect(recipient.reload).to be_unsubscribed
    expect(recipient.attempts).to eq(0)
    expect(recipient.last_error).to be_nil
  end

  it 'preserves an opt-out committed while the provider accepts the message' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(sender).to receive(:deliver) do
      EmailCampaignRecipient.find(recipient.id).update!(status: :unsubscribed)
      'accepted-optout-in-flight'
    end
    engine.perform
    expect(recipient.reload).to be_unsubscribed
    expect(recipient.ses_message_id).to eq('accepted-optout-in-flight')
    expect(recipient.sent_at).to be_present
  end

  it 'never retries a 5xx merely because its body names a throttling exception' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(sender).to receive(:deliver).and_raise(EmailCampaigns::Ses::Error, '503 ThrottlingException')
    engine.perform
    expect(recipient.reload).to be_failed
    expect(recipient.attempts).to eq(0)
  end

  it 'releases only its own demonstrably undispatched claim after a manual pause' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    gate = EmailCampaigns::DeliveryClaim.new(campaign)
    expect(gate.claim(recipient)).to eq(:claimed)
    campaign.pause!
    expect(EmailCampaigns::DeliveryClaim.new(campaign).dispatch_allowed?(recipient)).to be(false)
    expect(recipient.reload).to be_sent
    expect(gate.dispatch_allowed?(recipient)).to be(false)
    expect(recipient.reload).to be_pending
  end

  it 'does not resurrect a canceled recipient after an explicit rejection arrives in flight' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    allow(sender).to receive(:deliver) do
      EmailCampaign.find(campaign.id).cancel!
      raise EmailCampaigns::Ses::Error, '429 explicit rejection'
    end
    engine.perform
    expect(recipient.reload).to be_suppressed
    expect(campaign.reload).to be_canceled
    expect(recipient.sent_at).to be_nil
  end

  it 'cannot release a claim after handing it off for external dispatch without a receipt' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    gate = EmailCampaigns::DeliveryClaim.new(campaign)
    expect(gate.claim(recipient)).to eq(:claimed)
    expect(gate.dispatch_allowed?(recipient)).to be(true)
    campaign.pause!
    expect(gate.dispatch_allowed?(recipient)).to be(false)
    expect(recipient.reload).to be_sent
  end

  context 'with direct inbox' do
    let(:inbox) { create(:channel_email).inbox }
    let(:campaign) { create(:email_campaign, account: inbox.account, delivery_mode: :direct_inbox, sender_inbox: inbox, status: :sending) }
    let(:sender) { instance_double(EmailCampaigns::DirectInbox::Sender, deliver: 'accepted-direct') }
    let(:direct) { EmailCampaigns::DirectInbox::RecipientSender.new(campaign, sender) }

    it 'shares hygiene checks, then admits a validated address despite a sticky SES provider block' do
      EmailProviderState.create!(provider_key: EmailCampaigns::Reputation::ProviderConfig.new.provider_key, status: 'blocked', blocked: true)
      expect(direct.deliver(recipient, Set.new)).to eq(:paused)
      expect(campaign).to be_paused
      expect(sender).not_to have_received(:deliver)
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      allow(EmailCampaigns::DeliveryJob).to receive(:perform_later)
      campaign.resume!
      expect(direct.deliver(recipient, Set.new)).to eq(:sent)
      expect(recipient.reload).to be_delivered
      expect(sender).to have_received(:deliver).once
    end

    it 'keeps validated recipients paused until an explicit persisted transition' do
      expect(direct.deliver(recipient)).to eq(:paused)
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      expect(direct.deliver(recipient)).to eq(:skipped)
      expect(sender).not_to have_received(:deliver)
      # Reproduce the original partial-update trap using the same instance.
      campaign.update!(status: :sending)
      expect(EmailCampaign.find(campaign.id)).to be_sending
      expect(direct.deliver(recipient)).to eq(:sent)
      expect(sender).to have_received(:deliver).once
    end

    it 'retains an accepted direct claim when receipt persistence fails and never dispatches it again' do
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      allow(recipient).to receive(:update_columns).and_call_original
      allow(recipient).to receive(:update_columns).with(hash_including(ses_message_id: 'accepted-direct'))
                                                  .and_raise(StandardError, 'synthetic receipt failure')
      expect(direct.deliver(recipient)).to eq(:sent)
      expect(recipient.reload).to have_attributes(status: 'sent', sent_at: nil, ses_message_id: nil)
      expect(direct.deliver(recipient)).to eq(:skipped)
      expect(sender).to have_received(:deliver).once
    end

    it 'preserves a direct opt-out committed while acceptance is in flight' do
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      allow(sender).to receive(:deliver) do
        EmailCampaignRecipient.find(recipient.id).update!(status: :unsubscribed)
        'accepted-direct-optout'
      end
      expect(direct.deliver(recipient)).to eq(:sent)
      expect(recipient.reload).to have_attributes(status: 'unsubscribed', ses_message_id: 'accepted-direct-optout', sent_at: be_present)
      expect(recipient.email_events.where(event_type: :delivered).count).to eq(1)
      expect(sender).to have_received(:deliver).once
    end

    it 'checks fresh quarantine and tenant protection after rendering without an old suppression snapshot' do
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      allow(direct).to receive(:render) do
        3.times do |i|
          EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email).record!(
            reason: 'temporary_failure', source: 'ses', event_key: "synthetic:#{i}"
          )
        end
        EmailReputationState.create!(account: account, blocked: true)
        { subject: 'Synthetic', body_html: '<p>Synthetic</p>' }
      end
      expect(direct.deliver(recipient, Set.new)).to eq(:suppressed)
      expect(sender).not_to have_received(:deliver)
      expect(recipient.reload).to be_suppressed
      expect(EmailReputationState.find_by!(account: account)).to be_blocked
    end

    it 'observes a tenant block published while direct inbox rendering is in progress' do
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      allow(direct).to receive(:render) do
        EmailReputationState.create!(account: account, blocked: true)
        { subject: 'Synthetic', body_html: '<p>Synthetic</p>' }
      end
      expect(direct.deliver(recipient)).to eq(:paused)
      expect(sender).not_to have_received(:deliver)
      expect(recipient.reload).to be_pending
      expect(campaign.reload.pause_reason).to include('kind' => 'reputation')
    end

    it 'does not fail a competing direct inbox claim when its own rendering raises' do
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      allow(direct).to receive(:render) do
        gate = EmailCampaigns::Reputation::Admission.new(EmailCampaign.find(campaign.id))
        expect(gate.claim!(EmailCampaignRecipient.find(recipient.id))).to be(true)
        raise 'synthetic rendering failure'
      end
      direct.deliver(recipient)
      expect(recipient.reload).to be_sent
      expect(recipient.last_error).to be_nil
      expect(sender).not_to have_received(:deliver)
    end

    it 'preserves opt-out on failure and refuses another recipient after a tenant flag' do
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      next_recipient = create(:email_campaign_recipient, email_campaign: campaign,
                                                         preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      allow(sender).to receive(:deliver) do
        EmailCampaignRecipient.find(recipient.id).update!(status: :unsubscribed)
        Account.find(account.id).update!(internal_attributes: { email_campaigns_paused: { reason: 'synthetic' } })
        raise Net::ReadTimeout, 'synthetic timeout'
      end
      direct.deliver(recipient)
      expect(recipient.reload).to be_unsubscribed
      expect(direct.deliver(next_recipient)).to eq(:paused)
      expect(next_recipient.reload).to be_pending
      expect(sender).to have_received(:deliver).once
    end
  end
end
