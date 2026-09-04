require 'rails_helper'

RSpec.describe EmailCampaigns::Ses::Sender do
  let(:account) { create(:account) }
  let(:client) { instance_double(EmailCampaigns::Ses::Client) }

  before do
    allow(EmailCampaigns::Ses::Client).to receive(:new).and_return(client)
    allow(client).to receive(:send_email).and_return({ 'MessageId' => 'ses-message-id' })
  end

  def identity_with(configuration_set)
    EmailSenderIdentity.create!(
      account: account, domain: 'hub2you.ai', from_email: 'comercial@hub2you.ai',
      provider: 'ses', status: :verified, ses_configuration_set: configuration_set
    )
  end

  def deliver(identity)
    described_class.new(identity).deliver(to: 'lead@example.com', subject: 'Oi', html_body: '<p>Oi</p>')
  end

  it 'sends with the configuration set stored on the identity' do
    deliver(identity_with('custom-set'))

    expect(client).to have_received(:send_email).with(hash_including(configuration_set: 'custom-set'))
  end

  # Legacy identities were provisioned before the column existed. Sending without a
  # configuration set makes SES publish no Delivery/Bounce/Complaint event at all, which
  # silently zeroes the campaign report and disables auto-suppression.
  it 'falls back to the system configuration set when the identity has none' do
    deliver(identity_with(nil))

    expect(client).to have_received(:send_email).with(
      hash_including(configuration_set: EmailCampaigns::Config.configuration_set_name)
    )
  end

  it 'refuses to send from an unverified identity' do
    identity = identity_with(nil)
    identity.update!(status: :verifying)

    expect { deliver(identity) }.to raise_error(EmailCampaigns::Ses::Error, /not verified/)
    expect(client).not_to have_received(:send_email)
  end
end
