require 'rails_helper'

RSpec.describe EmailCampaigns::DeliveryEngine do # rubocop:disable RSpec/SpecFilePathFormat -- hygiene integration across both senders
  let(:campaign) { create(:email_campaign, status: :sending) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign) }
  let(:client) { EmailCampaigns::Ses::Client.new }
  let(:engine) { described_class.new(campaign) }
  let(:sender) { EmailCampaigns::Ses::Sender.new(campaign.sender_identity) }
  let(:endpoint) { 'https://email.us-east-1.amazonaws.com/v2/email/outbound-emails' }

  before do
    allow(EmailCampaigns::Config).to receive_messages(enabled?: true, region: 'us-east-1')
    allow(EmailCampaigns::Ses::Client).to receive(:new).and_return(client)
    # No credential chain/signature lookup: WebMock exercises only provider response handling.
    allow(client).to receive(:signer).and_return(instance_double(Aws::Sigv4::Signer,
                                                                 sign_request: instance_double(Aws::Sigv4::Signature, headers: {})))
    allow(engine).to receive(:unsubscribe_headers).and_return({})
    allow(engine).to receive(:render).and_return(subject: 'Example', body_html: '<p>Example</p>')
    allow(EmailCampaigns::Tracking::Injector).to receive(:new).and_return(instance_double(EmailCampaigns::Tracking::Injector,
                                                                                          perform: '<p>Example</p>'))
  end

  it 'blocks a recipient imported before a suppression, even with an old empty Set' do
    stale_set = EmailSuppression.suppressed_set_for(campaign.account)
    recipient
    EmailCampaigns::SuppressionRegistry.new(account: campaign.account, email: recipient.email).block!(
      reason: 'unsubscribe', source: 'link', event_key: 'optout'
    )
    request = stub_request(:post, endpoint).to_return(status: 200, body: '{"MessageId":"example"}')
    engine.send(:deliver_one, recipient, sender, stale_set)
    expect(recipient.reload).to be_suppressed
    expect(request).not_to have_been_requested
  end

  it 'rechecks after rendering and before the network call' do
    allow(engine).to receive(:render) do
      EmailSuppression.create!(account: campaign.account, email: recipient.email, reason: 'manual')
      { subject: 'Example', body_html: '<p>Example</p>' }
    end
    request = stub_request(:post, endpoint).to_return(status: 200, body: '{"MessageId":"example"}')
    engine.send(:deliver_one, recipient, sender)
    expect(recipient.reload).to be_suppressed
    expect(request).not_to have_been_requested
  end

  it 'checks fresh suppression for the second recipient of the same run' do
    first = recipient
    second = create(:email_campaign_recipient, email_campaign: campaign)
    request = stub_request(:post, endpoint).to_return do
      EmailSuppression.create!(account: campaign.account, email: second.email, reason: 'manual')
      { status: 200, body: '{"MessageId":"first-message"}' }
    end
    engine.send(:deliver_one, first, sender, Set.new)
    engine.send(:deliver_one, second, sender, Set.new)
    expect(first.reload).to be_sent
    expect(second.reload).to be_suppressed
    expect(request).to have_been_requested.once
  end

  it 'does not requeue or redispatch an ambiguous timeout' do
    request = stub_request(:post, endpoint).to_timeout
    engine.send(:deliver_one, recipient, sender)
    expect(recipient.reload).to be_failed
    expect(recipient.attempts).to eq(0)
    engine.send(:deliver_one, recipient, sender)
    expect(request).to have_been_requested.once
  end

  it 'preserves the claim if post-send persistence fails' do
    request = stub_request(:post, endpoint).to_return(status: 200, body: '{"MessageId":"accepted"}')
    allow(recipient).to receive(:update_columns).and_call_original
    allow(recipient).to receive(:update_columns).with(hash_including(ses_message_id: 'accepted')).and_raise(StandardError, 'write failed')
    engine.send(:deliver_one, recipient, sender)
    expect(recipient.reload).to be_sent
    engine.send(:deliver_one, recipient, sender)
    expect(request).to have_been_requested.once
  end

  it 'does not rewrite previously dispatched recipients when later suppressed' do
    recipient.update!(status: :delivered, ses_message_id: 'already-dispatched')
    EmailSuppression.create!(account: campaign.account, email: recipient.email, reason: 'manual')
    engine.send(:deliver_one, recipient, sender)
    expect(recipient.reload).to be_delivered
  end

  it 'blocks DirectInbox after rendering with a stale preloaded Set' do
    direct_sender = instance_double(EmailCampaigns::DirectInbox::Sender, deliver: 'direct-message')
    direct = EmailCampaigns::DirectInbox::RecipientSender.new(campaign, direct_sender)
    allow(direct).to receive(:render) do
      EmailSuppression.create!(account: campaign.account, email: recipient.email, reason: 'manual')
      { subject: 'Example', body_html: '<p>Example</p>' }
    end
    direct.deliver(recipient, Set.new)
    expect(recipient.reload).to be_suppressed
    expect(direct_sender).not_to have_received(:deliver)
  end

  it 'pauses enforce with pending validation and does not finalize' do
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce') do
      request = stub_request(:post, endpoint).to_return(status: 200, body: '{}')
      engine.send(:deliver_one, recipient, sender)
      campaign.reload.finalize!
      expect(campaign.reload).to be_paused
      expect(campaign.hygiene_pause_reason).to eq('hygiene_validation_required')
      expect(recipient.reload).to be_pending
      expect(request).not_to have_been_requested
    end
  end

  it 'refuses to claim a pending row containing evidence of a previous dispatch' do
    recipient.update!(ses_message_id: 'previous-dispatch', sent_at: 1.day.ago)
    request = stub_request(:post, endpoint).to_return(status: 200, body: '{}')
    engine.send(:deliver_one, recipient, sender)
    expect(request).not_to have_been_requested
    expect(recipient.reload.ses_message_id).to eq('previous-dispatch')
  end

  it 'keeps an opt-out arriving during DirectInbox provider dispatch' do
    direct_sender = instance_double(EmailCampaigns::DirectInbox::Sender)
    direct = EmailCampaigns::DirectInbox::RecipientSender.new(campaign, direct_sender)
    allow(direct).to receive(:render).and_return(subject: 'Example', body_html: '<p>Example</p>')
    allow(direct).to receive(:unsubscribe_headers).and_return({})
    allow(direct_sender).to receive(:deliver) do
      EmailCampaignRecipient.find(recipient.id).update!(status: :unsubscribed)
      'accepted-message'
    end
    direct.deliver(recipient)
    expect(recipient.reload).to be_unsubscribed
    expect(recipient.ses_message_id).to eq('accepted-message')
  end

  it 'still retries an explicit 429 rejection without an ambiguous resend' do
    request = stub_request(:post, endpoint).to_return(status: 429, body: '{"message":"throttled"}')
    engine.send(:deliver_one, recipient, sender)
    expect(recipient.reload).to be_pending
    expect(recipient.attempts).to eq(1)
    expect(request).to have_been_requested.once
  end

  it 'does not return a canceled recipient to pending after rendering' do
    allow(engine).to receive(:render) do
      campaign.cancel!
      { subject: 'Example', body_html: '<p>Example</p>' }
    end
    request = stub_request(:post, endpoint).to_return(status: 200, body: '{}')
    engine.send(:deliver_one, recipient, sender)
    expect(campaign.reload).to be_canceled
    expect(recipient.reload).to be_suppressed
    expect(request).not_to have_been_requested
  end

  it 'does not let another worker finalize while a recipient is claimed but not dispatched' do
    gate = EmailCampaigns::DeliveryClaim.new(campaign)
    expect(gate.claim(recipient)).to eq(:claimed)
    EmailCampaign.find(campaign.id).finalize!
    expect(campaign.reload).to be_sending
    expect(gate.dispatch_allowed?(recipient)).to be true
  end
end
